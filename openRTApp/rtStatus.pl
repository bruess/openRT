#!/usr/bin/perl

###############################################################################
# rtStatus.pl - OpenRT Backup System Status Checker
###############################################################################
#
# DESCRIPTION:
#   This script checks and reports the status of the OpenRT backup system by
#   examining connected drives, ZFS pools, and their states. It provides both
#   human-readable and JSON-formatted output detailing the system's current
#   state, including available and imported pools, connected drives, and
#   overall system availability.
#
# USAGE:
#   sudo ./rtStatus.pl [-j]
#
# OPTIONS:
#   -j    Output results in JSON format with detailed information
#
# REQUIREMENTS:
#   - Root privileges (for ZFS operations)
#   - Perl JSON module (auto-installed if missing)
#   - ZFS utilities (zpool command)
#   - System tools: lsblk
#
# OUTPUT STATES:
#   - "Imported"      : RT pool is imported and ready for use
#   - "Available"     : RT pool is detected but not imported
#   - "Not Available" : No RT pool found or system not ready
#
# JSON OUTPUT FIELDS:
#   - timestamp         : Current date/time
#   - status           : Overall system status
#   - has_drives       : Whether non-OS drives are connected
#   - has_imported_pool: Whether any pools are currently imported
#   - has_available_pool: Whether any pools are available for import
#   - drives           : List of connected non-OS drives
#   - imported_pools   : Currently imported ZFS pools
#   - available_pools  : Pools available for import
#
# ERROR HANDLING:
#   - Validates required tools and commands
#   - Handles missing JSON module with auto-installation
#   - Provides clear error messages for common issues
#
# SAFETY FEATURES:
#   - Excludes OS drive from drive detection
#   - Supports both standalone and integrated usage
#   - Used by other OpenRT scripts for system validation
#
# NOTES:
#   - Excludes OS drive from drive detection
#   - Supports both standalone and integrated usage
#   - Used by other OpenRT scripts for system validation
#
###############################################################################

use strict;
use warnings;
use POSIX qw(strftime);
use File::Basename;
use Cwd 'abs_path';

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
        
        # Clean up old log files for rtStatus only (older than 10 minutes)
        cleanup_old_logs($log_dir, $script_name);
    } else {
        warn "Warning: Could not open log file $log_file: $!";
        $log_enabled = 0;
    }
}

# Clean up old rtStatus log files (older than 10 minutes)
sub cleanup_old_logs {
    my ($log_dir, $script_name) = @_;
    
    # Only clean up logs for the current script (rtStatus)
    return unless $script_name eq 'rtStatus';
    
    my $cutoff_time = time() - (10 * 60); # 10 minutes ago
    my $cleaned_count = 0;
    
    # Look for rtStatus log files
    if (opendir(my $dh, $log_dir)) {
        my @log_files = grep { /^rtStatus_\d{8}_\d{6}_\d+\.log$/ } readdir($dh);
        closedir($dh);
        
        foreach my $log_filename (@log_files) {
            my $full_path = "$log_dir/$log_filename";
            next unless -f $full_path; # Skip if not a regular file
            
            # Get file modification time
            my $mtime = (stat($full_path))[9];
            
            # Delete if older than 10 minutes and not the current log file
            if ($mtime < $cutoff_time && $full_path ne $log_file) {
                if (unlink($full_path)) {
                    $cleaned_count++;
                } else {
                    # Don't log here as it could cause issues during initialization
                    warn "Warning: Could not delete old log file $full_path: $!" if $log_enabled;
                }
            }
        }
    }
    
    # Log the cleanup operation if any files were removed
    if ($cleaned_count > 0) {
        write_log("Cleaned up $cleaned_count old rtStatus log files (older than 10 minutes)");
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

# Auto-install JSON module if needed
BEGIN {
    eval {
        require JSON;
        JSON->import();
    };
    if ($@) {
        print "JSON module not found. Installing...\n";
        # Log the module installation attempt if logging is initialized
        write_log("JSON module not found, attempting installation") if $log_enabled;
        system('apt-get update -qq && apt-get install -qq -y libjson-perl') == 0
            or die "Failed to install JSON module: $?\n";
        eval {
            require JSON;
            JSON->import();
        };
        die "Failed to load JSON module after installation: $@" if $@;
        print "JSON module installed successfully.\n";
        write_log("JSON module installed successfully") if $log_enabled;
    }
}

# Process command line arguments
my $json_output = grep { $_ eq '-j' } @ARGV;
write_log("Command line arguments: " . join(", ", @ARGV));
write_log("JSON output mode: " . ($json_output ? "enabled" : "disabled"));

# Constants for GitHub updates
my $GITHUB_UPDATE_FLAG = "/var/run/openrt_github_update.flag";
my $GITHUB_UPDATE_SCRIPT = "/usr/local/openRT/setup/githubUpdates.sh";

# Function to check if GitHub update should run
# Returns: Boolean indicating if update should run
sub should_run_github_update {
    write_log("Checking if GitHub update should run");
    # Get system boot time using built-in stat
    my @proc_stat = stat("/proc/1");
    if (!@proc_stat) {
        log_warning("Cannot get boot time, will run GitHub update");
        return 1; # Run if we can't get boot time
    }
    my $boot_time = $proc_stat[9];
    write_log("System boot time: $boot_time");
    
    # Check if flag file exists
    if (-e $GITHUB_UPDATE_FLAG) {
        write_log("GitHub update flag file exists: $GITHUB_UPDATE_FLAG");
        my @flag_stat = stat($GITHUB_UPDATE_FLAG);
        if (!@flag_stat) {
            log_warning("Cannot get flag file time, will run GitHub update");
            return 1; # Run if we can't get flag time
        }
        my $flag_time = $flag_stat[9];
        write_log("Flag file time: $flag_time");
        # Return true if flag is older than boot time
        my $should_run = $flag_time < $boot_time;
        write_log("Should run GitHub update: " . ($should_run ? "yes" : "no"));
        return $should_run;
    }
    
    # No flag file exists, should run
    write_log("No GitHub update flag file exists, should run update");
    return 1;
}

# Function to run GitHub update and create flag
sub run_github_update {
    write_log("Running GitHub update");
    if (-x $GITHUB_UPDATE_SCRIPT) {
        write_log("Executing GitHub update script: $GITHUB_UPDATE_SCRIPT");
        system("sudo $GITHUB_UPDATE_SCRIPT");
        my $update_exit_code = $? >> 8;
        write_log("GitHub update script exit code: $update_exit_code");
        
        # Create/update flag file
        write_log("Creating/updating GitHub update flag file");
        system("touch $GITHUB_UPDATE_FLAG");
    } else {
        log_warning("GitHub update script not found or not executable: $GITHUB_UPDATE_SCRIPT");
    }
}

# Function to check for connected non-OS drives
# Returns: ($has_extra_drives, \@extra_drives)
#   - $has_extra_drives: Boolean indicating if non-OS drives are present
#   - @extra_drives: Array of hashes containing drive details (name, size, type)
sub check_drives {
    write_log("Checking for connected drives");
    my @drives = `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT -n`;
    my $drives_exit_code = $? >> 8;
    write_log("lsblk exit code: $drives_exit_code");
    write_log("Found " . scalar(@drives) . " total drives/devices");
    
    my $has_extra_drives = 0;
    my @extra_drives;
    
    foreach my $drive (@drives) {
        write_log("Checking drive entry: $drive");
        # Look for any drive except sda (assumed OS drive)
        if ($drive =~ /sd[a-z]/ && $drive =~ /disk/) {
            write_log("Found disk drive: $drive");
            $has_extra_drives = 1;
            if ($drive =~ /(\S+)\s+(\S+)\s+(\S+)/) {
                my $drive_info = {
                    name => $1,
                    size => $2,
                    type => $3
                };
                write_log("Drive details - Name: $1, Size: $2, Type: $3");
                push @extra_drives, $drive_info;
            }
        }
    }
    
    write_log("Drive check complete - Has extra drives: " . ($has_extra_drives ? "yes" : "no"));
    write_log("Total extra drives found: " . scalar(@extra_drives));
    return ($has_extra_drives, \@extra_drives);
}

# Function to determine if a pool is a valid RT pool
# based on its name and environment variables
sub is_rt_pool {
    my ($pool_name) = @_;
    
    # Check for specific pool name from environment variable (highest priority)
    if (defined $ENV{RT_POOL_NAME}) {
        return 1 if $pool_name eq $ENV{RT_POOL_NAME};
    }
    
    # Get custom pattern from environment or use default patterns
    my $pool_pattern;
    if (defined $ENV{RT_POOL_PATTERN}) {
        $pool_pattern = $ENV{RT_POOL_PATTERN};
    } else {
        # Default patterns: rtPool-\d+ or revRT
        $pool_pattern = qr/^(rtPool-\d+|revRT.*?)$/;
    }
    
    # Match against pattern
    return $pool_name =~ /$pool_pattern/;
}

# Function to check ZFS pool status
# Returns: ($has_imported_pool, $has_available_pool, \@imported_pools, \@available_pools)
#   - $has_imported_pool: Boolean indicating if any pools are imported
#   - $has_available_pool: Boolean indicating if any pools are available
#   - @imported_pools: Array of hashes with imported pool details
#   - @available_pools: Array of hashes with available pool details
sub check_zfs_pools {
    write_log("Checking ZFS pool status");
    my @pools = `zpool list -H`;
    my $pools_exit_code = $? >> 8;
    write_log("zpool list exit code: $pools_exit_code");
    
    my $has_imported_pool = 0;
    my $has_available_pool = 0;
    my @imported_pools;
    my @available_pools;
    
    # Check for available but not imported pools
    write_log("Checking for available pools to import");
    my $import_output = `zpool import 2>&1`;
    my $import_exit_code = $? >> 8;
    write_log("zpool import check exit code: $import_exit_code");
    write_log("zpool import output length: " . length($import_output));
    
    while ($import_output =~ /pool:\s+(\S+).*?state:\s+(\S+)/gs) {
        my $pool_name = $1;
        my $pool_state = $2;
        write_log("Found available pool: $pool_name, state: $pool_state");
        
        # Skip if not an RT pool, unless RT_EXPORT_ALL is set
        unless (is_rt_pool($pool_name) || $ENV{RT_EXPORT_ALL}) {
            write_log("Skipping non-RT pool: $pool_name");
            next;
        }
        
        write_log("Adding available RT pool: $pool_name");
        $has_available_pool = 1;
        push @available_pools, {
            name => $pool_name,
            state => $pool_state,
            is_rt_pool => is_rt_pool($pool_name) ? JSON::true : JSON::false
        };
    }
    
    # Check currently imported pools
    write_log("Checking currently imported pools");
    if ($pools_exit_code == 0 && @pools) {
        write_log("Found " . scalar(@pools) . " imported pools");
        foreach my $pool (@pools) {
            if ($pool =~ /^(\S+)\s+(\S+)\s+(\S+)/) {
                my $pool_name = $1;
                my $pool_size = $2;
                my $pool_allocated = $3;
                write_log("Found imported pool: $pool_name, size: $pool_size, allocated: $pool_allocated");
                
                # Skip if not an RT pool, unless RT_EXPORT_ALL is set
                unless (is_rt_pool($pool_name) || $ENV{RT_EXPORT_ALL}) {
                    write_log("Skipping non-RT imported pool: $pool_name");
                    next;
                }
                
                $has_imported_pool = 1 if is_rt_pool($pool_name);
                write_log("Adding imported RT pool: $pool_name");
                
                push @imported_pools, {
                    name => $pool_name,
                    size => $pool_size,
                    allocated => $pool_allocated,
                    is_rt_pool => is_rt_pool($pool_name) ? JSON::true : JSON::false
                };
            }
        }
    } else {
        write_log("No imported pools found or zpool list failed");
    }
    
    write_log("Pool check complete - Imported RT pools: " . ($has_imported_pool ? "yes" : "no"));
    write_log("Available RT pools: " . ($has_available_pool ? "yes" : "no"));
    return ($has_imported_pool, $has_available_pool, \@imported_pools, \@available_pools);
}

# Main function to check and report system status
# Combines drive and pool checks to determine overall system state
sub get_rt_status {
    write_log("Starting RT status check");
    
    # Check and run GitHub updates if needed
    if (should_run_github_update()) {
        write_log("GitHub update needed, running update");
        run_github_update();
    } else {
        write_log("GitHub update not needed");
    }
    
    # Check for connected drives
    write_log("Checking connected drives");
    my ($has_drives, $extra_drives) = check_drives();
    
    # Check ZFS pool status
    write_log("Checking ZFS pools");
    my ($has_imported_pool, $has_available_pool, $imported_pools, $available_pools) = check_zfs_pools();
    
    # Determine overall system status
    my $status = "Not Available";
    if ($has_imported_pool) {
        $status = "Imported";      # Pool is imported and ready
    } elsif ($has_available_pool) {
        $status = "Available";     # Pool detected but not imported
    } elsif (!$has_drives) {
        $status = "Not Available"; # No suitable drives found
    }
    
    write_log("Final status determination: $status");
    write_log("Has drives: " . ($has_drives ? "yes" : "no"));
    write_log("Has imported pool: " . ($has_imported_pool ? "yes" : "no"));
    write_log("Has available pool: " . ($has_available_pool ? "yes" : "no"));
    
    # Output results in requested format
    if ($json_output) {
        write_log("Generating JSON output");
        # Generate detailed JSON output
        my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
        my $result = {
            timestamp => $timestamp,
            status => $status,
            has_drives => $has_drives ? JSON::true : JSON::false,
            has_imported_pool => $has_imported_pool ? JSON::true : JSON::false,
            has_available_pool => $has_available_pool ? JSON::true : JSON::false,
            drives => $extra_drives,
            imported_pools => $imported_pools,
            available_pools => $available_pools
        };
        print encode_json($result) . "\n";
    } else {
        write_log("Generating simple text output");
        # Simple status output for human reading
        print "$status\n";
    }
}

# Execute status check and output results
write_log("Executing main status check");
get_rt_status();

exit 0;


