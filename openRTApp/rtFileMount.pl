#!/usr/bin/perl

###############################################################################
# rtFileMount.pl - OpenRT Backup Volume Mount Utility
###############################################################################
#
# DESCRIPTION:
#   This script is responsible for mounting backup volumes from OpenRT backup
#   snapshots. It can mount individual snapshots or all snapshots for a given
#   agent, handling both Windows NTFS volumes stored in .datto files and
#   managing ZFS clones for accessing the backup data. For each .datto file,
#   it also creates a VMDK descriptor file to enable easy importing into
#   virtual machines.
#
# USAGE:
#   sudo ./rtFileMount.pl [-cleanup[=agent_name]] [-j] agent_name [snapshot_epoch|all]
#   sudo ./rtFileMount.pl cleanup                 # Same as -cleanup=1
#
# OPTIONS:
#   -cleanup[=agent_name]  Clean up mounts for specific agent or all if no agent specified
#   -j                     Output results in JSON format
#   agent_name            Name, hostname, or ID of the backup agent
#   snapshot_epoch        Unix timestamp of desired snapshot (optional)
#                        Use 'all' to mount all snapshots
#
# EXAMPLES:
#   # Mount latest snapshot for agent "server1"
#   sudo ./rtFileMount.pl server1
#
#   # Mount specific snapshot by timestamp
#   sudo ./rtFileMount.pl server1 1634567890
#
#   # Mount all snapshots for agent "server1"
#   sudo ./rtFileMount.pl server1 all
#
#   # Clean up all mounts for agent "server1"
#   sudo ./rtFileMount.pl -cleanup=server1
#
#   # Clean up all mounts (two equivalent methods)
#   sudo ./rtFileMount.pl -cleanup
#   sudo ./rtFileMount.pl cleanup
#
# DIRECTORY STRUCTURE:
#   /rtMount/                      - Base mount directory
#   └── [agent_name]/             - Agent-specific directory
#       └── [snapshot_date]/      - Snapshot-specific directory
#           └── [volume_name]/    - Individual volume mount points
#   /rtMount/zfs_block/           - Temporary ZFS clone mount points
#                                  Contains .datto files and their .vmdk descriptors
#
# REQUIREMENTS:
#   - Root privileges
#   - Perl modules: JSON, File::Path, POSIX, Getopt::Long, File::Basename
#   - System tools: mount, umount, zfs, losetup, fdisk
#
# PROCESS FLOW:
#   1. Parse command line arguments and validate input
#   2. Clean up any existing mounts for the target agent
#   3. Retrieve agent metadata using rtMetadata.pl
#   4. Identify target snapshots based on input parameters
#   5. For each snapshot:
#      a. Create ZFS clone for accessing .datto files
#      b. Mount clone to temporary location
#      c. Process each volume in the snapshot:
#         - Create VMDK descriptor file next to .datto file
#         - Analyze partition layout using fdisk
#         - Calculate correct partition offset
#         - Mount volume using appropriate filesystem type
#   6. Output results (plain text or JSON)
#
# ERROR HANDLING:
#   - Validates root privileges
#   - Checks for required metadata
#   - Verifies successful mounting of volumes
#   - Provides detailed error messages and debug output
#
# NOTES:
#   - Snapshot dates are converted from Unix timestamps to YYYY-MM-DD_HH-MM-SS format
#   - Windows volumes are mounted read-only using NTFS filesystem
#   - Debug output can be controlled via $debug flag
#   - VMDK descriptor files are created alongside .datto files for VM import
#   - VMDK files use relative paths to reference their .datto files
#
###############################################################################

use strict;
use warnings;
use JSON;
use File::Path qw(make_path remove_tree);
use POSIX qw(strftime);
use Getopt::Long;
use File::Basename;
use Cwd 'abs_path';

# Debug flag - Controls detailed output for troubleshooting
my $debug = 1;  # Set to 0 to disable debug output

# Parse command line options
my $cleanup_mode = 0;
my $json_output = 0;
my $cleanup_agent = '';
GetOptions(
    'cleanup:s' => \$cleanup_agent,  # Optional agent name for cleanup
    'j' => \$json_output            # JSON output format flag
) or die "Usage: $0 [-cleanup[=agent_name]] [-j] agent_name [snapshot_epoch|all]\n";

# Handle 'cleanup' as a positional argument
if (!$cleanup_agent && @ARGV > 0 && $ARGV[0] eq 'cleanup') {
    $cleanup_agent = '1';  # Set to same value as -cleanup=1
    shift @ARGV;  # Remove the 'cleanup' argument
}

# Debug print function for controlled output of diagnostic information
sub debug {
    my ($msg) = @_;
    print "DEBUG: $msg\n" if $debug && !$json_output;
}

# Data structure for storing mount information when using JSON output
my $mount_info = {
    status => "success",
    message => "",
    mounts => []
};

# Comprehensive cleanup function that handles:
# - Unmounting of backup volumes
# - Destroying ZFS clones
# - Detaching loop devices
# - Removing mount directories
sub cleanup_mounts {
    my ($base_dir, $agent_name, $is_cleanup_mode) = @_;
    debug("Starting cleanup" . ($agent_name ? " for agent: $agent_name" : " for all agents"));
    
    my @cleaned = ();  # Track all cleaned resources for reporting
    
    # Step 1: First unmount all NTFS volumes
    # These are typically NTFS volumes mounted from .datto files
    my @mounts = `mount | grep $base_dir`;
    foreach my $mount (@mounts) {
        if ($mount =~ /on\s+(\S+)\s+type\s+fuseblk/) {
            my $mount_point = $1;
            
            # Filter by agent name if specified
            if ($agent_name) {
                next unless $mount_point =~ m|$base_dir/$agent_name|;
            }
            
            debug("Unmounting NTFS volume: $mount_point");
            system("umount -f -l $mount_point 2>/dev/null");
            push @cleaned, $mount_point;
        }
    }
    
    # Give system time to process unmounts
    sleep(2);
    
    # Step 2: Clean up loop devices
    # These are used to mount the .datto files
    debug("Cleaning up loop devices");
    my @losetup = `losetup -a | grep .datto`;
    foreach my $loop (@losetup) {
        if ($loop =~ /^(\/dev\/loop\d+):\s+.*\.datto/) {
            my $loop_dev = $1;
            debug("Detaching loop device: $loop_dev");
            system("losetup -d $loop_dev 2>/dev/null");
            push @cleaned, $loop_dev;
        }
    }
    
    # Step 3: Clean up ZFS clones and mounts
    # These are temporary clones created to access .datto files
    my @clones = `zfs list -H -o name | grep mount_`;
    foreach my $clone (@clones) {
        chomp($clone);
        # Filter by agent name if specified
        if ($agent_name && $agent_name ne '1') {
            next unless $clone =~ m|/agents/$agent_name/|;
        }
        
        debug("Processing ZFS clone: $clone");
        
        # Get mount point before unmounting
        my $mountpoint = `zfs get -H -o value mountpoint $clone 2>/dev/null`;
        chomp($mountpoint);
        
        # First try unmounting if mounted
        my $is_mounted = `zfs get -H -o value mounted $clone 2>/dev/null` =~ /yes/;
        if ($is_mounted) {
            debug("Clone is mounted at $mountpoint, attempting unmount");
            system("zfs unmount -f $clone 2>/dev/null");
            sleep(1);
        }
        
        # Try to destroy the clone
        system("zfs destroy -f $clone 2>/dev/null");
        
        # If clone still exists, try more aggressive cleanup
        if (`zfs list -H -o name $clone 2>/dev/null`) {
            debug("Clone persists, trying aggressive cleanup");
            # Force unmount any remaining processes
            system("fuser -k $mountpoint 2>/dev/null") if $mountpoint;
            sleep(1);
            system("zfs unmount -f $clone 2>/dev/null");
            system("zfs destroy -R -f $clone 2>/dev/null");
            
            # Final verification
            if (`zfs list -H -o name $clone 2>/dev/null`) {
                debug("Warning: Unable to fully clean up clone: $clone");
            }
        }
        push @cleaned, $clone;
    }
    
    # Step 4: Remove mount directories, but only after everything is unmounted
    if ($agent_name && $agent_name ne '1') {
        my $agent_dir = "$base_dir/$agent_name";
        my $agent_temp_dir = "$base_dir/zfs_block/$agent_name";
        
        # Check if any mounts still exist before removing
        my @remaining_mounts = `mount | grep -E "$agent_dir|$agent_temp_dir"`;
        if (@remaining_mounts) {
            debug("Warning: Found remaining mounts, attempting force unmount");
            foreach my $mount (@remaining_mounts) {
                if ($mount =~ /on\s+(\S+)\s+/) {
                    my $mount_point = $1;
                    system("umount -f -l $mount_point 2>/dev/null");
                }
            }
            sleep(2);  # Give time for unmounts to complete
        }
        
        # Now try to remove directories
        if (-d $agent_dir) {
            debug("Removing directory: $agent_dir");
            system("rm -rf $agent_dir 2>/dev/null");
            if (-d $agent_dir) {
                debug("Warning: Failed to remove $agent_dir");
            }
        }
        if (-d $agent_temp_dir) {
            debug("Removing temporary directory: $agent_temp_dir");
            system("rm -rf $agent_temp_dir 2>/dev/null");
            if (-d $agent_temp_dir) {
                debug("Warning: Failed to remove $agent_temp_dir");
            }
        }
    }
    
    # Output results based on format preference
    if ($json_output && $is_cleanup_mode) {
        print encode_json({
            status => "success",
            message => $agent_name ? "Cleanup completed for agent: $agent_name" : "Cleanup completed for all agents",
            cleaned => \@cleaned
        }) . "\n";
        exit 0;
    }
    
    print ($agent_name ? "Cleanup completed for agent: $agent_name\n" : "Cleanup completed for all agents.\n") unless $json_output;
}

# Get absolute path of script directory for locating related scripts
my $script_dir = dirname(abs_path($0));

# Validate root privileges required for mount operations
die "This script must be run as root\n" unless $> == 0;

# Define base directories for mount operations
my $mount_base = "/rtMount";                # Main directory for mounted volumes
my $zfs_block_base = "$mount_base/zfs_block";  # Temporary location for ZFS mounts

# Handle cleanup mode if specified
if ($cleanup_agent ne '') {
    cleanup_mounts($mount_base, $cleanup_agent eq '1' ? '' : $cleanup_agent, 1);
    exit 0;
}

# Parse and validate command line arguments
my $agent_name = shift @ARGV;
my $snapshot_epoch = shift @ARGV;

die "Usage: $0 [-cleanup[=agent_name]] [-j] agent_name [snapshot_epoch|all]\n" unless $agent_name;

# Perform initial cleanup of existing mounts for this agent
# This ensures we start with a clean slate
debug("Performing initial cleanup for agent: $agent_name");
cleanup_mounts($mount_base, $agent_name, 0);

# Create required mount directories
make_path($mount_base) unless -d $mount_base;
make_path($zfs_block_base) unless -d $zfs_block_base;

# Initialize array for tracking target snapshots to process
my @target_snapshots = ();

# Convert epoch timestamp to human-readable date format
# This is used for creating readable directory names
my $snapshot_date = ($snapshot_epoch && $snapshot_epoch ne 'all') ? 
    strftime("%Y-%m-%d_%H-%M-%S", localtime($snapshot_epoch)) : 
    "latest";

debug("Agent name: $agent_name");
debug("Snapshot epoch: " . ($snapshot_epoch // "none") . " ($snapshot_date)");

# Retrieve agent metadata using rtMetadata.pl
# This provides information about available snapshots and volumes
debug("Retrieving agent metadata...");
my $metadata_script = "$script_dir/rtMetadata.pl";
die "Cannot find rtMetadata.pl\n" unless -f $metadata_script;

# Execute metadata script and capture JSON output
my $metadata_json = `perl "$metadata_script" -j`;
die "Failed to get metadata\n" if $? != 0;

# Parse metadata JSON response
my $metadata;
eval {
    $metadata = decode_json($metadata_json);
};
if ($@) {
    debug("JSON decode error: $@");
    debug("Raw JSON: $metadata_json");
    die "Failed to parse metadata JSON: $@\n";
}

# Search for the agent in metadata using various identifiers
# Agent can be found by hostname, name, or agent ID
my $agent_info;
my $agent_id_found;
foreach my $agent_id (keys %{$metadata->{agents}}) {
    my $agent = $metadata->{agents}->{$agent_id};
    debug("Checking agent: " . ($agent->{hostname} // "unknown") . " / " . 
          ($agent->{name} // "unknown") . " / " . 
          ($agent->{agentId} // "unknown"));
    
    # Match against any of the agent identifiers
    if ($agent->{hostname} eq $agent_name || 
        $agent->{name} eq $agent_name || 
        $agent->{agentId} eq $agent_name) {
        $agent_info = $agent;
        $agent_id_found = $agent_id;
        debug("Found matching agent with ID: $agent_id");
        
        # Debug the volumes data structure
        debug("Raw volumes data: " . ($agent->{volumes} ? ref($agent->{volumes}) || "scalar" : "undefined"));
        if ($agent->{volumes}) {
            if (ref($agent->{volumes}) eq 'ARRAY') {
                debug("Agent volumes found: " . scalar(@{$agent->{volumes}}));
                foreach my $vol (@{$agent->{volumes}}) {
                    debug("Volume info: GUID=" . ($vol->{guid} // "none") . 
                          ", Mount=" . ($vol->{mountpoints} // "none") . 
                          ", FS=" . ($vol->{filesystem} // "none"));
                }
            } elsif (ref($agent->{volumes}) eq 'HASH') {
                # Handle case where volumes is a hash
                debug("Volumes is a hash with keys: " . join(", ", keys %{$agent->{volumes}}));
                my @vol_array;
                foreach my $key (keys %{$agent->{volumes}}) {
                    my $vol = $agent->{volumes}->{$key};
                    push @vol_array, $vol if ref($vol) eq 'HASH';
                }
                $agent->{volumes} = \@vol_array;
                debug("Converted " . scalar(@vol_array) . " volumes from hash to array");
            } else {
                # Handle unexpected data type
                debug("WARNING: Volumes data is neither array nor hash. Type: " . ref($agent->{volumes}));
                $agent->{volumes} = [];
            }
        } else {
            debug("No volumes data found for agent");
            $agent->{volumes} = [];
        }
        last;
    }
}

# Validate agent was found in metadata
die "Agent '$agent_name' not found in metadata\n" unless $agent_info;

# Get RT pool name from metadata
# This is the ZFS pool containing all backup data
my $rt_pool = $metadata->{pool_name};
die "No RT pool found in metadata\n" unless $rt_pool;
debug("Using RT pool: $rt_pool");

# Set up ZFS dataset paths for accessing snapshots
my $agents_dataset = "$rt_pool/home/agents";
my $snapshot_path = "$agents_dataset/$agent_name";

# If agent was found by ID, use the ID for the snapshot path instead of name
if ($agent_id_found && $agent_id_found ne $agent_name) {
    $snapshot_path = "$agents_dataset/$agent_id_found";
    debug("Using agent ID for snapshot path: $snapshot_path");
}

debug("Checking ZFS dataset: $snapshot_path");

# Retrieve list of available snapshots for this agent
debug("Retrieving snapshot list...");
my @snapshots = `zfs list -H -t snapshot -o name $snapshot_path 2>/dev/null`;
chomp(@snapshots);

# Determine which snapshots to process based on user input
if ($snapshot_epoch && $snapshot_epoch eq 'all') {
    # Process all available snapshots
    debug("Processing all available snapshots");
    @target_snapshots = @snapshots;
} elsif ($snapshot_epoch) {
    # Find snapshot closest to specified timestamp
    debug("Looking for snapshot closest to epoch $snapshot_epoch");
    my $closest_snapshot;
    my $smallest_diff = undef;
    
    # Compare each snapshot's timestamp to find the closest match
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
    # Default to latest snapshot if no epoch specified
    my $latest = $snapshots[-1];
    debug("Using latest snapshot: " . ($latest // "none"));
    @target_snapshots = ($latest) if $latest;
}

# Validate that we found at least one snapshot to process
die "No snapshots found for agent '$agent_name'\n" unless @target_snapshots;

# Function to create a VMDK descriptor file for a raw disk image
sub create_vmdk_descriptor {
    my ($datto_file, $vmdk_path, $size_bytes) = @_;
    
    # Convert size to sectors (512 bytes per sector)
    my $sectors = int($size_bytes / 512);
    
    # Create VMDK descriptor content
    my $vmdk_content = qq{# Disk DescriptorFile
version=1
encoding="UTF-8"
CID=fffffffe
parentCID=ffffffff
isNativeSnapshot="no"
createType="monolithicFlat"

# Extent description
RW $sectors FLAT "$datto_file" 0

# The Disk Data Base
#DDB

ddb.adapterType = "lsilogic"
ddb.geometry.cylinders = "1024"
ddb.geometry.heads = "255"
ddb.geometry.sectors = "63"
ddb.longContentID = "0123456789abcdef0123456789abcdef"
ddb.virtualHWVersion = "4"};

    # Write the descriptor file
    open(my $fh, '>', $vmdk_path) or return 0;
    print $fh $vmdk_content;
    close($fh);
    
    return 1;
}

# Process each target snapshot
foreach my $target_snapshot (@target_snapshots) {
    # Initialize tracking structure for this snapshot
    my $snapshot_info = {
        snapshot => $target_snapshot,
        date => "",
        zfs_clone => "",
        temp_mount => "",
        final_mount => "",
        volumes => []
    };
    
    # Extract and convert snapshot timestamp to readable format
    my $snap_epoch = ($target_snapshot =~ /\@(\d+)$/)[0] // 'unknown';
    my $snapshot_date = $snap_epoch ne 'unknown' ? 
        strftime("%Y-%m-%d_%H-%M-%S", localtime($snap_epoch)) : 
        "unknown";
    
    $snapshot_info->{date} = $snapshot_date;
    
    debug("\nProcessing snapshot: $target_snapshot ($snapshot_date)");
    
    # Set up mount points for this snapshot
    my $zfs_block_mount = "$zfs_block_base/$agent_name/$snapshot_date";
    my $final_mount_base = "$mount_base/$agent_name/$snapshot_date";
    make_path($zfs_block_mount);
    make_path($final_mount_base);
    
    $snapshot_info->{temp_mount} = $zfs_block_mount;
    $snapshot_info->{final_mount} = $final_mount_base;
    
    # Create and mount ZFS clone once for all volumes in this snapshot
    my $clone_name = $snapshot_path . "/mount_" . $$ . "_" . $snap_epoch;
    $snapshot_info->{zfs_clone} = $clone_name;
    debug("Creating temporary clone for .datto access: $clone_name");
    
    # Check if mount point is already in use
    my $mount_exists = `mount | grep -F "$zfs_block_mount"`;
    if ($mount_exists) {
        debug("Mount point $zfs_block_mount is already in use, cleaning up first");
        my @existing_mounts = `zfs list -H -o name,mountpoint | grep -F "$zfs_block_mount"`;
        foreach my $existing (@existing_mounts) {
            if ($existing =~ /^(\S+)\s+/) {
                my $existing_clone = $1;
                debug("Removing existing clone: $existing_clone");
                system("zfs unmount -f $existing_clone 2>/dev/null");
                system("zfs destroy -f $existing_clone 2>/dev/null");
            }
        }
        sleep(1);
    }
    
    # Clean up any existing clone with the same name
    my $existing_clone = `zfs list -H -o name $clone_name 2>/dev/null`;
    if ($existing_clone) {
        debug("Found existing clone with same name, destroying it first");
        system("zfs unmount -f $clone_name 2>/dev/null");
        system("zfs destroy -f $clone_name 2>/dev/null");
        sleep(1);
    }
    
    # Create and mount the clone once for this snapshot
    my $clone_mounted = 0;
    if ($json_output) {
        system("zfs clone $target_snapshot $clone_name 2>/dev/null");
        system("zfs set mountpoint=$zfs_block_mount $clone_name 2>/dev/null");
        
        my $is_mounted = `zfs get -H -o value mounted $clone_name 2>/dev/null` =~ /yes/;
        if (!$is_mounted) {
            system("zfs mount $clone_name 2>/dev/null");
        }
        $clone_mounted = `mount | grep $zfs_block_mount` ? 1 : 0;
    } else {
        # Even in non-JSON mode, suppress the "already mounted" warnings
        system("zfs clone $target_snapshot $clone_name 2>/dev/null");
        system("zfs set mountpoint=$zfs_block_mount $clone_name 2>/dev/null");
        system("zfs mount $clone_name 2>/dev/null");
        $clone_mounted = `mount | grep $zfs_block_mount` ? 1 : 0;
    }
    
    # Verify clone was mounted successfully
    unless ($clone_mounted) {
        warn "Warning: Failed to mount ZFS clone at $zfs_block_mount, skipping this snapshot\n";
        next;
    }
    debug("ZFS clone mounted successfully to temporary location");
    
    # Now process each volume using the already mounted clone
    my $volumes = $agent_info->{volumes} || [];
    $volumes = [] unless ref($volumes) eq 'ARRAY';
    
    foreach my $vol (@{$volumes}) {
        # Initialize tracking structure for this volume
        my $volume_info = {
            guid => $vol->{guid},
            mountpoint => $vol->{mountpoints},
            filesystem => $vol->{filesystem},
            status => "not_mounted",
            mount_path => "",
            error => "",
            vmdk_path => ""
        };
        
        debug("\nProcessing volume: " . ($vol->{mountpoints} // "unknown"));
        
        # Extract required volume information
        my $guid = $vol->{guid};
        my $mountpoint = $vol->{mountpoints};
        my $filesystem = $vol->{filesystem};
        
        # Validate required volume information is present
        unless ($guid && $mountpoint) {
            debug("Skipping volume due to missing required information");
            $volume_info->{error} = "Missing required volume information";
            push @{$snapshot_info->{volumes}}, $volume_info;
            next;
        }
        
        debug("Volume GUID: $guid");
        debug("Mountpoint: $mountpoint");
        debug("Filesystem: $filesystem");
        
        # Sanitize mountpoint for use in directory name
        # Remove problematic characters like colons and slashes
        $mountpoint =~ s/[:\\\/]//g;
        my $mount_path = "$final_mount_base/$mountpoint";
        make_path($mount_path);
        
        # Locate and process the .datto file for this volume
        my $datto_file = "$zfs_block_mount/$guid.datto";
        if (-f $datto_file) {
            debug("Found .datto file: $datto_file");
            
            # Create VMDK descriptor file next to the .datto file
            my $vmdk_path = "$zfs_block_mount/$guid.vmdk";
            my $datto_size = -s $datto_file;
            if (create_vmdk_descriptor("$guid.datto", $vmdk_path, $datto_size)) {
                debug("Created VMDK descriptor at: $vmdk_path");
                $volume_info->{vmdk_path} = $vmdk_path;
            } else {
                warn "Warning: Failed to create VMDK descriptor for $datto_file\n" unless $json_output;
                $volume_info->{error} .= " Failed to create VMDK descriptor.";
            }
            
            # Analyze partition layout using fdisk
            debug("Analyzing partition layout with fdisk...");
            my $fdisk_output = `fdisk -l "$datto_file" 2>&1`;
            debug("fdisk output:\n$fdisk_output");
            
            # Calculate partition offset for mounting
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
                    $volume_info->{error} = "Failed to determine partition offset";
                    push @{$snapshot_info->{volumes}}, $volume_info;
                    next;
                }
            } else {
                warn "Warning: Could not determine sector size from fdisk output\n";
                $volume_info->{error} = "Failed to determine sector size";
                push @{$snapshot_info->{volumes}}, $volume_info;
                next;
            }
            
            # Construct mount command with calculated offset
            # Using NTFS read-only mount for Windows volumes
            my $mount_cmd = "mount -t ntfs -o ro,offset=$offset $datto_file $mount_path";
            debug("Mounting with command: $mount_cmd");
            
            # Ensure mount point is clean before mounting
            system("umount -f $mount_path 2>/dev/null");
            
            # Attempt to mount the volume
            system($mount_cmd);
            
            # Verify mount was successful
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
            $volume_info->{error} = "Missing .datto file";
        }
        
        # Add volume results to snapshot tracking
        push @{$snapshot_info->{volumes}}, $volume_info;
    }
    
    # Add snapshot results to overall tracking
    push @{$mount_info->{mounts}}, $snapshot_info;
    
    # Output success message for this snapshot
    unless ($json_output) {
        print "\nSnapshot mount operations completed for $snapshot_date\n";
        print "Files are mounted at: $final_mount_base/\n";
        print "ZFS clone is mounted at: $zfs_block_mount\n";
    }
}

# Output final results in requested format
if ($json_output) {
    # Return structured JSON output
    print encode_json($mount_info) . "\n";
} else {
    # Return human-readable output
    print "\nAll mount operations completed.\n";
    print "To clean up all mounts, run: $0 -cleanup\n";
    
    # Show final mount points for verification
    debug("\nFinal mount points:");
    system("mount | grep $mount_base");
}
