#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use File::Path qw(make_path remove_tree);
use POSIX qw(strftime);
use Getopt::Long;
use File::Basename;
use Cwd 'abs_path';

# Debug flag
my $debug = 1;  # Set to 0 to disable debug output

# Command line options
my $cleanup_mode = 0;
my $json_output = 0;
GetOptions(
    'cleanup' => \$cleanup_mode,
    'j' => \$json_output
) or die "Usage: $0 [-cleanup] [-j] agent_name [snapshot_epoch|all]\n";

# Debug print function
sub debug {
    my ($msg) = @_;
    print "DEBUG: $msg\n" if $debug && !$json_output;
}

# Store mount information for JSON output
my $mount_info = {
    status => "success",
    message => "",
    mounts => []
};

# Cleanup function
sub cleanup_mounts {
    my ($base_dir) = @_;
    debug("Starting cleanup of $base_dir");
    
    my @cleaned = ();
    
    # First unmount any .datto mounts
    my @mounts = `mount | grep $base_dir`;
    foreach my $mount (@mounts) {
        if ($mount =~ /on\s+(\S+)\s+/) {
            my $mount_point = $1;
            next if $mount_point =~ /\/temp_zfs\//;  # Skip ZFS temp mounts for now
            debug("Unmounting: $mount_point");
            system("umount -f $mount_point 2>/dev/null");
            push @cleaned, $mount_point;
        }
    }
    
    # Now unmount and clean up ZFS clones
    my @clones = `zfs list -H -o name | grep mount_`;
    foreach my $clone (@clones) {
        chomp($clone);
        debug("Destroying ZFS clone: $clone");
        system("zfs unmount $clone 2>/dev/null");
        system("zfs destroy -f $clone 2>/dev/null");
        push @cleaned, $clone;
    }
    
    # Remove the mount directories
    if (-d $base_dir) {
        debug("Removing directory: $base_dir");
        remove_tree($base_dir);
    }
    
    if ($json_output) {
        print encode_json({
            status => "success",
            message => "Cleanup completed",
            cleaned => \@cleaned
        }) . "\n";
        exit 0;
    }
    
    print "Cleanup completed.\n" unless $json_output;
}

# Get script directory
my $script_dir = dirname(abs_path($0));

# Check if running as root
die "This script must be run as root\n" unless $> == 0;

# Base mount directory
my $mount_base = "/rtMount";
my $temp_zfs_base = "$mount_base/temp_zfs";  # New temporary location for ZFS mounts

# If in cleanup mode, just clean up and exit
if ($cleanup_mode) {
    cleanup_mounts($mount_base);
    exit 0;
}

# Parse command line arguments
my $agent_name = shift @ARGV;
my $snapshot_epoch = shift @ARGV;

die "Usage: $0 [-cleanup] [-j] agent_name [snapshot_epoch|all]\n" unless $agent_name;

# Convert epoch to human readable date if provided
my $snapshot_date = ($snapshot_epoch && $snapshot_epoch ne 'all') ? 
    strftime("%Y-%m-%d_%H-%M-%S", localtime($snapshot_epoch)) : 
    "latest";

debug("Agent name: $agent_name");
debug("Snapshot epoch: " . ($snapshot_epoch // "none") . " ($snapshot_date)");

# Create base mount directory if it doesn't exist
debug("Creating base mount directory: $mount_base");
make_path($mount_base) unless -d $mount_base;

# Get metadata using rtMetadata.pl
debug("Running rtMetadata.pl...");
my $metadata_script = "$script_dir/rtMetadata.pl";
die "Cannot find rtMetadata.pl\n" unless -f $metadata_script;

my $metadata_json = `perl "$metadata_script" -j`;
die "Failed to get metadata\n" if $? != 0;

my $metadata;
eval {
    $metadata = decode_json($metadata_json);
};
if ($@) {
    debug("JSON decode error: $@");
    debug("Raw JSON: $metadata_json");
    die "Failed to parse metadata JSON: $@\n";
}

# Find the agent in metadata
my $agent_info;
foreach my $agent_id (keys %{$metadata->{agents}}) {
    my $agent = $metadata->{agents}->{$agent_id};
    debug("Checking agent: " . ($agent->{hostname} // "unknown") . " / " . ($agent->{name} // "unknown"));
    if ($agent->{hostname} eq $agent_name || $agent->{name} eq $agent_name) {
        $agent_info = $agent;
        debug("Found matching agent with ID: $agent_id");
        last;
    }
}

die "Agent '$agent_name' not found in metadata\n" unless $agent_info;

# Get RT pool name from metadata
my $rt_pool = $metadata->{pool_name};
die "No RT pool found in metadata\n" unless $rt_pool;
debug("Using RT pool: $rt_pool");

# First mount the ZFS dataset to get access to .datto files
my $agents_dataset = "$rt_pool/home/agents";
my $snapshot_path = "$agents_dataset/$agent_name";
debug("Checking ZFS dataset: $snapshot_path");

# Get list of snapshots for this agent
debug("Getting snapshot list...");
my @snapshots = `zfs list -H -t snapshot -o name $snapshot_path 2>/dev/null`;
chomp(@snapshots);

my @target_snapshots;
if ($snapshot_epoch && $snapshot_epoch eq 'all') {
    # Use all snapshots
    debug("Using all snapshots");
    @target_snapshots = @snapshots;
} elsif ($snapshot_epoch) {
    # Find the snapshot closest to the specified time
    debug("Looking for snapshot closest to epoch $snapshot_epoch");
    my $closest_snapshot;
    my $smallest_diff = undef;
    
    foreach my $snap (@snapshots) {
        if ($snap =~ /\@(\d+)$/) {
            my $snap_time = $1;
            my $diff = abs($snap_time - $snapshot_epoch);
            debug("  Snapshot time: $snap_time, diff: $diff");
            
            if (!defined($smallest_diff) || $diff < $smallest_diff) {
                $smallest_diff = $diff;
                $closest_snapshot = $snap;
                debug("  New closest snapshot: $snap (diff: $diff)");
            }
        }
    }
    
    @target_snapshots = ($closest_snapshot) if $closest_snapshot;
} else {
    # Use the latest snapshot
    my $latest = $snapshots[-1];
    debug("Using latest snapshot: " . ($latest // "none"));
    @target_snapshots = ($latest) if $latest;
}

die "No snapshots found for agent '$agent_name'\n" unless @target_snapshots;

foreach my $target_snapshot (@target_snapshots) {
    my $snapshot_info = {
        snapshot => $target_snapshot,
        date => "",
        zfs_clone => "",
        temp_mount => "",
        final_mount => "",
        volumes => []
    };
    
    # Extract epoch from snapshot name for date conversion
    my $snap_epoch = ($target_snapshot =~ /\@(\d+)$/)[0] // 'unknown';
    my $snapshot_date = $snap_epoch ne 'unknown' ? 
        strftime("%Y-%m-%d_%H-%M-%S", localtime($snap_epoch)) : 
        "unknown";
    
    $snapshot_info->{date} = $snapshot_date;
    
    debug("\nProcessing snapshot: $target_snapshot ($snapshot_date)");
    
    # Mount the snapshot to access .datto files
    my $temp_zfs_mount = "$temp_zfs_base/$agent_name/$snapshot_date";
    my $final_mount_base = "$mount_base/$agent_name/$snapshot_date";
    make_path($temp_zfs_mount);
    make_path($final_mount_base);
    
    $snapshot_info->{temp_mount} = $temp_zfs_mount;
    $snapshot_info->{final_mount} = $final_mount_base;
    
    my $clone_name = $snapshot_path . "/mount_" . $$ . "_" . $snap_epoch;
    $snapshot_info->{zfs_clone} = $clone_name;
    debug("Creating temporary clone for .datto access: $clone_name");
    
    # First check if clone already exists
    my $existing_clone = `zfs list -H -o name $clone_name 2>/dev/null`;
    if ($existing_clone) {
        debug("Found existing clone, destroying it first");
        system("zfs unmount $clone_name 2>/dev/null");
        system("zfs destroy -f $clone_name 2>/dev/null");
    }
    
    # Create and mount the clone to temporary location
    system("zfs clone $target_snapshot $clone_name");
    system("zfs set mountpoint=$temp_zfs_mount $clone_name");
    system("zfs mount $clone_name");
    
    # Verify the mount
    my $mount_check = `mount | grep $temp_zfs_mount`;
    unless ($mount_check) {
        warn "Warning: Failed to mount ZFS clone at $temp_zfs_mount, skipping this snapshot\n";
        next;
    }
    debug("ZFS clone mounted successfully to temporary location");
    
    # Now process each volume
    foreach my $vol (@{$agent_info->{volumes}}) {
        my $volume_info = {
            guid => $vol->{guid},
            mountpoint => $vol->{mountpoints},
            filesystem => $vol->{filesystem},
            status => "not_mounted",
            mount_path => "",
            error => ""
        };
        
        debug("\nProcessing volume: " . ($vol->{mountpoints} // "unknown"));
        
        # Get volume information
        my $guid = $vol->{guid};
        my $mountpoint = $vol->{mountpoints};
        my $filesystem = $vol->{filesystem};
        
        debug("Volume GUID: $guid");
        debug("Mountpoint: $mountpoint");
        debug("Filesystem: $filesystem");
        
        # Clean up mountpoint for directory name
        $mountpoint =~ s/[:\\\/]//g;
        my $mount_path = "$final_mount_base/$mountpoint";
        make_path($mount_path);
        
        # Find corresponding .datto file in temporary ZFS mount
        my $datto_file = "$temp_zfs_mount/$guid.datto";
        if (-f $datto_file) {
            debug("Found .datto file: $datto_file");
            
            # Use fdisk to read partition table
            debug("Reading partition table with fdisk...");
            my $fdisk_output = `fdisk -l "$datto_file" 2>&1`;
            debug("fdisk output:\n$fdisk_output");
            
            my $offset = 0;
            if ($fdisk_output =~ /Sector size.*:\s+(\d+)/i) {
                my $sector_size = $1;
                debug("Detected sector size: $sector_size");
                
                # Look for partition start sector in either GPT or MBR format
                if ($fdisk_output =~ /\.datto1\s+\*?\s*(\d+)\s+\d+\s+\d+/) {
                    my $start_sector = $1;
                    $offset = $start_sector * $sector_size;
                    debug("Found partition starting at sector $start_sector, offset: $offset bytes");
                } else {
                    warn "Warning: Could not find partition start sector in fdisk output\n";
                    next;
                }
            } else {
                warn "Warning: Could not determine sector size from fdisk output\n";
                next;
            }
            
            # Mount the .datto file with detected offset
            my $mount_cmd = "mount -t ntfs -o ro,offset=$offset $datto_file $mount_path";
            debug("Mounting with command: $mount_cmd");
            
            # First try to unmount if already mounted
            system("umount -f $mount_path 2>/dev/null");
            
            # Then try to mount
            system($mount_cmd);
            
            # Verify mount
            my $mount_check = `mount | grep $mount_path`;
            if ($mount_check) {
                debug("Volume mounted successfully");
                $volume_info->{status} = "mounted";
                $volume_info->{mount_path} = $mount_path;
            } else {
                warn "Warning: Mount verification failed for $mount_path\n" unless $json_output;
                $volume_info->{status} = "failed";
                $volume_info->{error} = "Mount verification failed";
            }
        } else {
            warn "Warning: Could not find .datto file for volume $mountpoint (GUID: $guid)\n";
        }
        
        push @{$snapshot_info->{volumes}}, $volume_info;
    }
    
    push @{$mount_info->{mounts}}, $snapshot_info;
    
    unless ($json_output) {
        print "\nSnapshot mount operations completed for $snapshot_date\n";
        print "Files are mounted at: $final_mount_base/\n";
        print "ZFS clone is mounted at: $temp_zfs_mount\n";
    }
}

if ($json_output) {
    print encode_json($mount_info) . "\n";
} else {
    print "\nAll mount operations completed.\n";
    print "To clean up all mounts, run: $0 -cleanup\n";
    
    # Final mount verification
    debug("\nFinal mount points:");
    system("mount | grep $mount_base");
}
