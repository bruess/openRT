#!/usr/bin/perl

###############################################################################
# rtMetadata.pl - OpenRT Backup Agent Metadata Collection Utility
###############################################################################
#
# DESCRIPTION:
#   This script collects and processes metadata for all backup agents in the
#   OpenRT backup system. It handles mounting of ZFS datasets, parsing of agent
#   information files, and provides detailed information about backup agents
#   and their snapshots. The script ensures proper cleanup of temporary mounts
#   and provides both human-readable and JSON output formats.
#
# USAGE:
#   sudo ./rtMetadata.pl [-j]
#
# OPTIONS:
#   -j, --json    Output results in JSON format only
#
# REQUIREMENTS:
#   - Root privileges
#   - Perl modules: JSON, PHP::Serialization (auto-installed if missing)
#   - ZFS utilities (zpool, zfs commands)
#   - Access to RT pool and agent datasets
#
# PROCESS FLOW:
#   1. Validate environment and requirements
#   2. Locate and verify RT pool status
#   3. Set up temporary mount points
#   4. Mount agent datasets
#   5. Process agent information files:
#      - Parse PHP serialized data
#      - Extract agent details
#      - Count snapshots
#   6. Combine and process metadata
#   7. Output results
#   8. Clean up mounts and temporary files
#
# ERROR HANDLING:
#   - Validates root privileges
#   - Checks for required Perl modules (auto-installs if missing)
#   - Verifies RT pool accessibility and status
#   - Ensures proper cleanup on exit or error
#
# NOTES:
#   - Uses temporary mount point under /tmp
#   - Automatically handles PHP serialized data format
#   - Provides snapshot counts for each agent
#   - Supports both detailed human-readable and JSON output
#
###############################################################################

use strict;
use warnings;
use File::Find;
use File::Basename;
use Cwd 'abs_path';
use Getopt::Long;

# Command line options
my $json_only = 0;
GetOptions(
    'j|json' => \$json_only,  # JSON output format flag
) or die "Usage: $0 [-j]\n";

# Global variables for cleanup management
my $agents_dataset;    # Path to agents dataset
my $temp_mount;        # Temporary mount point
my $cleanup_needed = 0;  # Cleanup flag

# Utility function to format output in human-readable form
sub format_human_readable {
    my ($label, $value, $indent) = @_;
    $indent //= 0;
    my $spacing = " " x $indent;
    return sprintf("%s%s: %s\n", $spacing, $label, $value);
}

# Comprehensive cleanup function to ensure proper unmounting and directory removal
sub cleanup {
    return unless $cleanup_needed;
    
    unless ($json_only) {
        print "\n" . "=" x 80 . "\n";
        print "Performing Cleanup Operations\n";
        print "=" x 80 . "\n";
    }
    
    if ($agents_dataset) {
        unless ($json_only) {
            print "• Unmounting agent datasets...\n";
        }
        my @datasets = `zfs list -H -o name -r $agents_dataset 2>/dev/null`;
        chomp(@datasets);
        foreach my $dataset (reverse @datasets) {
            unless ($json_only) {
                print "  - Unmounting: $dataset\n";
            }
            system("zfs unmount $dataset 2>/dev/null");
            system("zfs set mountpoint=none $dataset 2>/dev/null");
        }
    }
    
    if ($temp_mount && -d $temp_mount) {
        unless ($json_only) {
            print "• Removing temporary mount directory: $temp_mount\n";
        }
        system("rmdir $temp_mount 2>/dev/null");
    }
    
    $cleanup_needed = 0;
    
    unless ($json_only) {
        print "\nCleanup completed successfully.\n";
    }
}

# Ensure cleanup runs on normal exit or die
END {
    cleanup();
}

# Get script directory
my $script_dir = dirname(abs_path($0));

# Auto-install required modules if needed
BEGIN {
    eval {
        require JSON;
        JSON->import();
        require PHP::Serialization;
        PHP::Serialization->import();
    };
    if ($@) {
        print "Required modules not found. Installing...\n" unless $json_only;
        system('apt-get update -qq && apt-get install -qq -y libjson-perl libphp-serialization-perl') == 0
            or die "Failed to install required modules: $?\n";
        eval {
            require JSON;
            JSON->import();
            require PHP::Serialization;
            PHP::Serialization->import();
        };
        die "Failed to load required modules after installation: $@" if $@;
    }
}

# Check if running as root
die "This script must be run as root\n" unless $> == 0;

# Function to identify RT pool
sub find_rt_pool {
    my @pools = `zpool list -H -o name`;
    chomp(@pools);
    foreach my $pool (@pools) {
        return $pool if $pool =~ /^rtPool-\d+$/;
    }
    return undef;
}

# Locate and validate RT pool
my $rt_pool = find_rt_pool();
die "No RT pool found. Please ensure the RT drive is connected and imported.\n" unless $rt_pool;

unless ($json_only) {
    print "\n" . "=" x 80 . "\n";
    print "OpenRT Metadata Collection\n";
    print "=" x 80 . "\n";
    print format_human_readable("RT Pool", $rt_pool);
}

# Verify RT pool status using rtStatus.pl
my $status_script = "$script_dir/rtStatus.pl";
die "Cannot find rtStatus.pl at $status_script\n" unless -f $status_script;

unless ($json_only) {
    print "\nVerifying RT Pool Status...\n";
}

my $status_check = `perl "$status_script" -j`;
my $status_result;
eval {
    $status_result = decode_json($status_check);
};
if ($@) {
    die "Failed to parse rtStatus.pl output: $status_check\n";
}

# Validate pool status
unless ($status_result && $status_result->{status} eq "Imported") {
    my $msg = "RT pool is not in the correct state. Current status: " . 
              ($status_result ? $status_result->{status} : "Unknown") . "\n";
    $msg .= "Please ensure the RT drive is connected and the pool is imported.\n";
    die $msg;
}

unless ($json_only) {
    print "✓ RT pool is imported and ready\n\n";
    print "=" x 80 . "\n";
    print "Setting Up Environment\n";
    print "=" x 80 . "\n";
}

# Initialize agents dataset path
$agents_dataset = "$rt_pool/home/agents";
my $agents_info = `zfs list -H -o name,mountpoint "$agents_dataset" 2>&1`;
if ($? != 0) {
    die "Agents dataset ($agents_dataset) does not exist in the RT pool.\n";
}

# Create temporary mount point
$temp_mount = "/tmp/rt_metadata_$$";  # Using PID for uniqueness
system("mkdir -p $temp_mount") == 0
    or die "Failed to create temporary mount directory: $?\n";

$cleanup_needed = 1;  # Mark for cleanup

unless ($json_only) {
    print format_human_readable("Temporary Mount Point", $temp_mount);
    print "\nPreparing Agent Datasets...\n";
}

# Unmount existing datasets
unless ($json_only) {
    print "• Unmounting existing agent datasets...\n";
}
my @agent_datasets = `zfs list -H -o name -r $agents_dataset`;
chomp(@agent_datasets);
foreach my $dataset (reverse @agent_datasets) {
    next if $dataset =~ /mount_/;  # Skip mount clones
    unless ($json_only) {
        print "  - Unmounting: $dataset\n";
    }
    system("zfs unmount $dataset 2>/dev/null");
}

# Set up new mount points
unless ($json_only) {
    print "\n• Setting up new mount points...\n";
}
foreach my $dataset (@agent_datasets) {
    next if $dataset =~ /mount_/;  # Skip mount clones
    
    my $relative_path = $dataset;
    $relative_path =~ s/^$agents_dataset\/?//;
    my $mount_path = $relative_path ? "$temp_mount/$relative_path" : $temp_mount;
    
    unless ($json_only) {
        print "  - Mounting $dataset to $mount_path\n";
    }
    
    system("mkdir -p $mount_path 2>/dev/null");
    if ($json_only) {
        system("zfs set mountpoint=$mount_path $dataset >/dev/null 2>&1");
        system("zfs mount $dataset >/dev/null 2>&1");
    } else {
        system("zfs set mountpoint=$mount_path $dataset") == 0
            or warn "    Warning: Failed to set mountpoint for $dataset: $?\n";
        system("zfs mount $dataset") == 0
            or warn "    Warning: Failed to mount $dataset: $?\n";
    }
}

# Function to count snapshots for an agent
sub count_agent_snapshots {
    my ($agent_id) = @_;
    my $dataset = "$agents_dataset/$agent_id";
    my @snapshots = `zfs list -H -t snapshot -o name -r $dataset 2>/dev/null`;
    chomp(@snapshots);
    @snapshots = grep { !/mount_/ } @snapshots;
    
    unless ($json_only) {
        print "  - Found " . scalar(@snapshots) . " snapshots for $agent_id\n";
    }
    
    return scalar(@snapshots);
}

# Initialize metadata storage
my %agent_metadata;
my $config_agent_id;

unless ($json_only) {
    print "\n" . "=" x 80 . "\n";
    print "Processing Agent Information\n";
    print "=" x 80 . "\n";
}

# Function to process agent information files
sub process_agent_info {
    my $file = $_;
    return unless $file =~ /\.agentInfo$/;
    
    my $dir = $File::Find::dir;
    my $full_path = $File::Find::name;
    
    unless ($json_only) {
        print "\nProcessing Agent File:\n";
        print "  Path: $full_path\n";
    }
    
    # Read and parse agent info file
    open(my $fh, '<', $full_path) or do {
        warn "  Warning: Cannot open $full_path: $!\n" unless $json_only;
        return;
    };
    my $content = do { local $/; <$fh> };
    close($fh);

    # Parse PHP serialized data
    my $agent_info;
    eval {
        $agent_info = PHP::Serialization::unserialize($content);
    };
    if ($@) {
        warn "  Warning: Failed to parse PHP serialized data in $full_path: $@\n" unless $json_only;
        return;
    }

    # Extract agent ID from path
    my $agent_id;
    if ($dir =~ m{/([^/]+)$}) {
        $agent_id = $1;
    } else {
        warn "  Warning: Could not extract agent ID from path: $dir\n" unless $json_only;
        return;
    }

    # Add metadata
    $agent_info->{agentId} = $agent_id;
    $agent_info->{agentInfoFile} = basename($full_path);
    
    # Count snapshots
    my $snapshot_count = count_agent_snapshots($agent_info->{name} || $agent_id);
    $agent_info->{snapshot_count} = $snapshot_count;
    
    # Store metadata
    $agent_metadata{$agent_id} = $agent_info;
    
    unless ($json_only) {
        print "\n  Agent Details:\n";
        print format_human_readable("ID", $agent_id, 4);
        print format_human_readable("Name", $agent_info->{name} // "N/A", 4);
        print format_human_readable("Hostname", $agent_info->{hostname} // "N/A", 4);
        print format_human_readable("OS Type", $agent_info->{osType} // "N/A", 4);
        print format_human_readable("Snapshots", $snapshot_count, 4);
        print format_human_readable("Last Backup", 
            $agent_info->{lastBackup} ? scalar(localtime($agent_info->{lastBackup})) : "Never", 4);
        
        if ($agent_info->{volumes} && ref($agent_info->{volumes}) eq 'ARRAY') {
            print "\n  Volumes:\n";
            foreach my $vol (@{$agent_info->{volumes}}) {
                print "    • " . ($vol->{mountpoints} // "Unknown Mount") . "\n";
                print "      Size: " . ($vol->{size} // "Unknown") . "\n";
                print "      Filesystem: " . ($vol->{filesystem} // "Unknown") . "\n";
            }
        }
        print "\n  " . "-" x 76 . "\n";
    }
}

# Find and process all agent info files
unless ($json_only) {
    print "Scanning for agent information files...\n";
}
find(\&process_agent_info, $temp_mount);

# Process and combine agent data
my %final_metadata;
foreach my $agent_id (keys %agent_metadata) {
    next if $agent_id eq 'config';
    
    if ($agent_metadata{config} && 
        $agent_metadata{config}->{name} eq $agent_id &&
        $agent_metadata{config}->{generated} >= ($agent_metadata{$agent_id}->{generated} || 0)) {
        $final_metadata{$agent_id} = $agent_metadata{config};
    } else {
        $final_metadata{$agent_id} = $agent_metadata{$agent_id};
    }
}

# Prepare final output
my $output = {
    success => JSON::true,
    timestamp => time(),
    pool_name => $rt_pool,
    agents_path => $temp_mount,
    agent_count => scalar(keys %final_metadata),
    agents => \%final_metadata
};

# Display summary in human-readable format
unless ($json_only) {
    print "\n" . "=" x 80 . "\n";
    print "Summary Report\n";
    print "=" x 80 . "\n";
    print format_human_readable("Total Agents Found", scalar(keys %final_metadata));
    print format_human_readable("RT Pool", $rt_pool);
    print format_human_readable("Temporary Path", $temp_mount);
    print format_human_readable("Timestamp", scalar(localtime($output->{timestamp})));
    print "\n";
}

# Output JSON data
my $json = JSON->new->utf8;
$json->pretty(1) if $json_only;
print $json->encode($output) . "\n";

# Cleanup handled by END block
