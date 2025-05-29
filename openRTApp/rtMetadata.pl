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
use POSIX qw(strftime);

# Global logging variables
my $log_enabled = 0;
my $log_file = '';
my $log_fh;

# Initialize logging functionality
sub init_logging {
    my $log_dir = "/usr/local/openRT/logs";
    return unless -d $log_dir;
    
    $log_enabled = 1;
    my $script_name = basename($0, '.pl');
    my $timestamp = strftime("%Y%m%d_%H%M%S", localtime);
    $log_file = "$log_dir/${script_name}_${timestamp}_$$.log";
    
    if (open($log_fh, '>>', $log_file)) {
        write_log("=== Starting $script_name at " . strftime("%Y-%m-%d %H:%M:%S", localtime) . " ===");
        write_log("Process ID: $$");
        write_log("Script location: " . abs_path($0));
        write_log("Working directory: " . Cwd::getcwd());
        write_log("User ID: $>");
        write_log("Command line: @ARGV");
    } else {
        warn "Warning: Could not open log file $log_file: $!";
        $log_enabled = 0;
    }
}

# Write to log file with timestamp
sub write_log {
    my ($message, $level) = @_;
    return unless $log_enabled && $log_fh;
    
    $level ||= 'INFO';
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print $log_fh "[$timestamp] [$level] $message\n";
    $log_fh->flush();
}

# Log errors and continue execution
sub log_error {
    my ($message) = @_;
    write_log($message, 'ERROR');
    warn "$message\n";
}

# Log warnings
sub log_warning {
    my ($message) = @_;
    write_log($message, 'WARN');
    warn "$message\n";
}

# Log debug information
sub log_debug {
    my ($message) = @_;
    write_log($message, 'DEBUG');
}

# Clean up logging on exit
sub cleanup_logging {
    if ($log_enabled && $log_fh) {
        write_log("=== Script completed at " . strftime("%Y-%m-%d %H:%M:%S", localtime) . " ===");
        close($log_fh);
    }
}

# Initialize logging
init_logging();

# Ensure cleanup on exit
END {
    cleanup_logging();
}

# Command line options
my $json_only = 0;
write_log("Parsing command line options...");
GetOptions(
    'j|json' => \$json_only,  # JSON output format flag
) or die "Usage: $0 [-j]\n";
write_log("JSON-only mode: " . ($json_only ? "enabled" : "disabled"));

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
    
    write_log("Starting cleanup operations");
    
    unless ($json_only) {
        print "\n" . "=" x 80 . "\n";
        print "Performing Cleanup Operations\n";
        print "=" x 80 . "\n";
    }
    
    if ($agents_dataset) {
        write_log("Unmounting agent datasets...");
        unless ($json_only) {
            print "• Unmounting agent datasets...\n";
        }
        my @datasets = `zfs list -H -o name -r $agents_dataset 2>/dev/null`;
        chomp(@datasets);
        write_log("Found " . scalar(@datasets) . " datasets to unmount");
        foreach my $dataset (reverse @datasets) {
            write_log("Unmounting dataset: $dataset");
            unless ($json_only) {
                print "  - Unmounting: $dataset\n";
            }
            system("zfs unmount $dataset 2>/dev/null");
            system("zfs set mountpoint=none $dataset 2>/dev/null");
        }
    }
    
    if ($temp_mount && -d $temp_mount) {
        write_log("Removing temporary mount directory: $temp_mount");
        unless ($json_only) {
            print "• Removing temporary mount directory: $temp_mount\n";
        }
        system("rmdir $temp_mount 2>/dev/null");
    }
    
    $cleanup_needed = 0;
    write_log("Cleanup operations completed");
    
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
write_log("Script directory: $script_dir");

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
        # Log the module installation attempt if logging is initialized
        write_log("Required modules not found, attempting installation") if $log_enabled;
        system('apt-get update -qq && apt-get install -qq -y libjson-perl libphp-serialization-perl') == 0
            or die "Failed to install required modules: $?\n";
        eval {
            require JSON;
            JSON->import();
            require PHP::Serialization;
            PHP::Serialization->import();
        };
        die "Failed to load required modules after installation: $@" if $@;
        write_log("Required modules installed successfully") if $log_enabled;
    }
}

# Check if running as root
write_log("Checking root privileges...");
if ($> != 0) {
    log_error("Script must be run as root (current UID: $>)");
    die "This script must be run as root\n";
}
write_log("Root privileges confirmed");

# Function to identify RT pool
sub find_rt_pool {
    write_log("Searching for RT pool...");
    # Check for specific pool name from environment variable (highest priority)
    if (defined $ENV{RT_POOL_NAME}) {
        my $pool_name = $ENV{RT_POOL_NAME};
        write_log("Checking for specific pool name from environment: $pool_name");
        my @pools = `zpool list -H -o name`;
        chomp(@pools);
        write_log("Available pools: " . join(", ", @pools));
        foreach my $pool (@pools) {
            if ($pool eq $pool_name) {
                write_log("Found specified pool: $pool");
                return $pool;
            }
        }
        # If specified pool not found, warn but continue search
        log_warning("Pool specified in RT_POOL_NAME ($pool_name) not found");
        print "Warning: Pool specified in RT_POOL_NAME ($pool_name) not found.\n" unless $json_only;
    }
    
    # Get custom pattern from environment or use default patterns
    my $pool_pattern;
    if (defined $ENV{RT_POOL_PATTERN}) {
        $pool_pattern = $ENV{RT_POOL_PATTERN};
        write_log("Using custom pool pattern from environment: $pool_pattern");
    } else {
        # Default patterns: rtPool-\d+ or revRT
        $pool_pattern = qr/^(rtPool-\d+|revRT.*?)$/;
        write_log("Using default pool pattern");
    }
    
    # Search for pool using pattern
    my @pools = `zpool list -H -o name`;
    chomp(@pools);
    write_log("Searching " . scalar(@pools) . " pools with pattern matching");
    foreach my $pool (@pools) {
        write_log("Checking pool: $pool");
        if ($pool =~ /$pool_pattern/) {
            write_log("Found matching RT pool: $pool");
            return $pool;
        }
    }
    
    write_log("No RT pool found matching criteria");
    return undef;
}

# Locate and validate RT pool
write_log("Locating RT pool...");
my $rt_pool = find_rt_pool();
if (!$rt_pool) {
    log_error("No RT pool found");
    die "No RT pool found. Please ensure the RT drive is connected and imported.\n";
}
write_log("RT pool located: $rt_pool");

unless ($json_only) {
    print "\n" . "=" x 80 . "\n";
    print "OpenRT Metadata Collection\n";
    print "=" x 80 . "\n";
    print format_human_readable("RT Pool", $rt_pool);
}

# Verify RT pool status using rtStatus.pl
my $status_script = "$script_dir/rtStatus.pl";
write_log("Status script path: $status_script");
if (!-f $status_script) {
    log_error("Cannot find rtStatus.pl at $status_script");
    die "Cannot find rtStatus.pl at $status_script\n";
}

unless ($json_only) {
    print "\nVerifying RT Pool Status...\n";
}

write_log("Executing status check...");
my $status_check = `perl "$status_script" -j`;
my $status_exit_code = $? >> 8;
write_log("Status script exit code: $status_exit_code");
write_log("Status script output: $status_check");

my $status_result;
eval {
    $status_result = decode_json($status_check);
};
if ($@) {
    log_error("Failed to parse rtStatus.pl output: $@");
    die "Failed to parse rtStatus.pl output: $status_check\n";
}

# Validate pool status
unless ($status_result && $status_result->{status} eq "Imported") {
    my $current_status = $status_result ? $status_result->{status} : "Unknown";
    log_error("RT pool is not in the correct state. Current status: $current_status");
    my $msg = "RT pool is not in the correct state. Current status: $current_status\n";
    $msg .= "Please ensure the RT drive is connected and the pool is imported.\n";
    die $msg;
}

write_log("RT pool status verified as imported and ready");

unless ($json_only) {
    print "✓ RT pool is imported and ready\n\n";
    print "=" x 80 . "\n";
    print "Setting Up Environment\n";
    print "=" x 80 . "\n";
}

# Initialize agents dataset path
# Check for custom agents path from environment variable
my $agents_path = $ENV{RT_AGENTS_PATH} || "home/agents";
$agents_dataset = "$rt_pool/$agents_path";
write_log("Agents path: $agents_path");
write_log("Agents dataset: $agents_dataset");

my $agents_info = `zfs list -H -o name,mountpoint "$agents_dataset" 2>&1`;
my $agents_check_exit = $? >> 8;
write_log("Agents dataset check exit code: $agents_check_exit");
write_log("Agents dataset info: $agents_info");

if ($agents_check_exit != 0) {
    log_error("Agents dataset ($agents_dataset) does not exist in the RT pool");
    die "Agents dataset ($agents_dataset) does not exist in the RT pool.\n";
}

unless ($json_only) {
    print format_human_readable("Agents Path", $agents_path);
    print format_human_readable("Agents Dataset", $agents_dataset);
}

# Create temporary mount point
$temp_mount = "/tmp/rt_metadata_$$";  # Using PID for uniqueness
write_log("Creating temporary mount point: $temp_mount");
my $mkdir_result = system("mkdir -p $temp_mount");
if ($mkdir_result != 0) {
    log_error("Failed to create temporary mount directory: $?");
    die "Failed to create temporary mount directory: $?\n";
}

$cleanup_needed = 1;  # Mark for cleanup
write_log("Cleanup flag set, temporary mount created successfully");

unless ($json_only) {
    print format_human_readable("Temporary Mount Point", $temp_mount);
    print "\nPreparing Agent Datasets...\n";
}

# Unmount existing datasets
write_log("Unmounting existing agent datasets...");
unless ($json_only) {
    print "• Unmounting existing agent datasets...\n";
}
my @agent_datasets = `zfs list -H -o name -r $agents_dataset`;
chomp(@agent_datasets);
write_log("Found " . scalar(@agent_datasets) . " agent datasets");

foreach my $dataset (reverse @agent_datasets) {
    next if $dataset =~ /mount_/;  # Skip mount clones
    write_log("Unmounting dataset: $dataset");
    unless ($json_only) {
        print "  - Unmounting: $dataset\n";
    }
    system("zfs unmount $dataset 2>/dev/null");
}

# Set up new mount points
write_log("Setting up new mount points...");
unless ($json_only) {
    print "\n• Setting up new mount points...\n";
}
foreach my $dataset (@agent_datasets) {
    next if $dataset =~ /mount_/;  # Skip mount clones
    
    my $relative_path = $dataset;
    $relative_path =~ s/^$agents_dataset\/?//;
    my $mount_path = $relative_path ? "$temp_mount/$relative_path" : $temp_mount;
    
    write_log("Setting up mount for dataset $dataset at $mount_path");
    unless ($json_only) {
        print "  - Mounting $dataset to $mount_path\n";
    }
    
    system("mkdir -p $mount_path 2>/dev/null");
    if ($json_only) {
        system("zfs set mountpoint=$mount_path $dataset >/dev/null 2>&1");
        system("zfs mount $dataset >/dev/null 2>&1");
    } else {
        my $mountpoint_result = system("zfs set mountpoint=$mount_path $dataset");
        if ($mountpoint_result != 0) {
            log_warning("Failed to set mountpoint for $dataset: $?");
            warn "    Warning: Failed to set mountpoint for $dataset: $?\n";
        }
        my $mount_result = system("zfs mount $dataset");
        if ($mount_result != 0) {
            log_warning("Failed to mount $dataset: $?");
            warn "    Warning: Failed to mount $dataset: $?\n";
        }
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
        ($agent_metadata{config}->{generated} || 0) >= ($agent_metadata{$agent_id}->{generated} || 0)) {
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
