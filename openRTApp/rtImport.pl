#!/usr/bin/perl

###############################################################################
# rtImport.pl - OpenRT ZFS Pool Import/Export Utility
###############################################################################
#
# DESCRIPTION:
#   This script manages the importing and exporting of ZFS pools in the OpenRT
#   backup system. It can automatically detect and import available pools,
#   handle specific device imports, and manage pool exports. The script includes
#   automatic detection of importable pools, force recovery options, and
#   protection against importing system pools.
#
# USAGE:
#   sudo ./rtImport.pl [import|export] [device_path] [-j]
#
# OPTIONS:
#   import|export    Command to either import or export ZFS pools
#   device_path     Optional path to specific device (e.g., /dev/sdb)
#   -j              Output results in JSON format
#
# EXAMPLES:
#   # Import all available pools
#   sudo ./rtImport.pl import
#
#   # Import pool from specific device
#   sudo ./rtImport.pl import /dev/sdb
#
#   # Export all pools (except system pool)
#   sudo ./rtImport.pl export
#
#   # Export pool from specific device
#   sudo ./rtImport.pl export /dev/sdb
#
#   # Get JSON output
#   sudo ./rtImport.pl import -j
#
# REQUIREMENTS:
#   - Root privileges
#   - Perl JSON module (auto-installed if missing)
#   - ZFS utilities (zpool, zfs commands)
#   - System tools: lsblk, mount
#
# PROCESS FLOW:
#   Import:
#   1. Validate command line arguments
#   2. If device specified:
#      a. Check device for importable pools
#      b. Attempt standard import
#      c. If failed, attempt force recovery
#   3. If no device specified:
#      a. Scan all available devices
#      b. Filter out system/OS drives
#      c. Attempt to import each found pool
#      d. Use force recovery if standard import fails
#
#   Export:
#   1. If device specified:
#      a. Find pool associated with device
#      b. Export the pool
#   2. If no device specified:
#      a. Get list of all pools
#      b. Export each pool (except system pool)
#
# ERROR HANDLING:
#   - Validates root privileges
#   - Checks for required Perl modules (auto-installs if missing)
#   - Verifies device accessibility
#   - Provides detailed error messages
#   - Supports both standard output and JSON error reporting
#
# SAFETY FEATURES:
#   - Skips OS/system drives during auto-detection
#   - Protects against exporting the root pool
#   - Verifies pool status before operations
#   - Checks if pools are already imported
#
# NOTES:
#   - Uses force recovery (-F) when standard import fails
#   - JSON output includes detailed status for each operation
#   - Automatically skips already imported pools
#   - Supports both single pool and batch operations
#
###############################################################################

use strict;
use warnings;
use File::Basename;
use Cwd 'abs_path';
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

# Validate root privileges required for ZFS operations
write_log("Checking root privileges...");
if ($> != 0) {
    log_error("Script must be run as root (current UID: $>)");
    die "This script must be run as root\n";
}
write_log("Root privileges confirmed");

# Initialize command line parameters
my $json_output = 0;
my $command = '';
my $device_path = '';

write_log("Parsing command line arguments...");
write_log("Arguments received: " . join(", ", @ARGV));

# First pass: Parse primary command arguments
# Looking for main commands (import/export) and device path
foreach my $arg (@ARGV) {
    next if $arg eq '-j';
    if (!$command && $arg =~ /^(import|export)$/) {
        $command = $arg;
        write_log("Command detected: $command");
    } elsif (!$device_path) {
        $device_path = $arg;
        write_log("Device path detected: $device_path");
    }
}

# Second pass: Check for JSON output flag
$json_output = grep { $_ eq '-j' } @ARGV;
write_log("JSON output mode: " . ($json_output ? "enabled" : "disabled"));

# Validate command format
unless ($command =~ /^(import|export)$/) {
    my $error = {
        error => "Invalid command",
        usage => "$0 [import|export] [device_path] [-j]"
    };
    log_error("Invalid command provided: " . ($command // 'none'));
    die($json_output ? encode_json($error) . "\n" : "Usage: $0 [import|export] [device_path] [-j]\n");
}

write_log("Command validation successful - executing $command" . ($device_path ? " on device $device_path" : ""));

# Output handling functions for consistent message formatting
sub output_message {
    my ($message, $success) = @_;
    write_log("Output message (success=$success): $message");
    if ($json_output) {
        print encode_json({
            success => $success,
            message => $message
        }) . "\n";
    } else {
        print "$message\n";
    }
}

# Error handling function for consistent error reporting
sub output_error {
    my ($message) = @_;
    log_error("Output error: $message");
    my $error = {
        success => JSON::false,
        error => $message
    };
    die($json_output ? encode_json($error) . "\n" : "$message\n");
}

# Utility function to identify the system's OS drive
# Returns the base device path (e.g., /dev/sda for /dev/sda1)
sub get_os_drive {
    my $os_drive = "";
    write_log("Identifying OS drive...");
    eval {
        # Get the device containing the root filesystem
        $os_drive = `mount | grep ' / ' | cut -d' ' -f1`;
        $os_drive =~ s/\d+$//; # Remove partition number to get base device
        chomp($os_drive);
    };
    if ($@) {
        log_error("Failed to get OS drive: $@");
        output_error("Failed to get OS drive: $@");
    }
    write_log("OS drive identified as: $os_drive");
    return $os_drive;
}

# Utility function to get detailed ZFS pool status
# Attempts to import pool in read-only mode to get status
sub get_pool_status {
    my ($device, $pool_name) = @_;
    my $status = "";
    eval {
        $status = `zpool import -d $device $pool_name 2>&1`;
    };
    if ($@) {
        output_error("Failed to get pool status: $@");
    }
    return $status;
}

# Main function to scan and identify importable ZFS pools
# Returns array of pool information hashes containing:
# - device: Device path
# - pool: Pool name
# - state: Pool state (ONLINE, DEGRADED, etc.)
# - status: Detailed pool status
# - type: Device type (disk, part, etc.)
# - size: Device size
sub find_importable_pools {
    my @pools;
    
    # Get OS drive to exclude from scan
    my $os_drive = get_os_drive();
    
    # Get detailed block device information using lsblk
    my $lsblk_json = "";
    eval {
        $lsblk_json = `lsblk -J -o NAME,TYPE,PKNAME,SIZE,MOUNTPOINT`;
    };
    if ($@) {
        output_error("Failed to get block device list: $@");
        return @pools;
    }
    
    # Parse lsblk JSON output
    my $devices;
    eval {
        $devices = decode_json($lsblk_json);
    };
    if ($@) {
        output_error("Failed to parse lsblk output: $@");
        return @pools;
    }
    
    # Recursive function to check each device and its children
    sub check_device {
        my ($device, $parent_name, $os_drive_ref, $pools_ref) = @_;
        my $dev_name = $device->{name};
        my $dev_type = $device->{type};
        my $mount = $device->{mountpoint} || '';
        
        # Skip system partitions and OS drive
        return if $mount eq '/' || $mount =~ m{^/boot};
        return if defined $parent_name && "/dev/$parent_name" eq $$os_drive_ref;
        return if "/dev/$dev_name" eq $$os_drive_ref;
        
        # Form complete device path
        my $dev_path = "/dev/$dev_name";
        
        # Check for ZFS pool signatures
        print "Checking $dev_type $dev_path (Size: $device->{size})\n" unless $json_output;
        my $zpool_output = "";
        eval {
            $zpool_output = `zpool import -d $dev_path 2>/dev/null`;
        };
        if ($@ || $? != 0) {
            return;
        }
        
        # Parse pool information if found
        if ($zpool_output =~ /pool:\s+(\S+)/m) {
            my $pool_name = $1;
            my $status = get_pool_status($dev_path, $pool_name);
            
            if ($status =~ /pool:\s+(\S+).*?state:\s+(\S+)/s) {
                push @$pools_ref, { 
                    device => $dev_path, 
                    pool => $1,
                    state => $2,
                    status => $status,
                    type => $dev_type,
                    size => $device->{size}
                };
            }
        }
        
        # Recursively process child devices
        if ($device->{children}) {
            foreach my $child (@{$device->{children}}) {
                check_device($child, $dev_name, $os_drive_ref, $pools_ref);
            }
        }
    }
    
    # Process all block devices
    if ($devices && $devices->{blockdevices}) {
        foreach my $device (@{$devices->{blockdevices}}) {
            eval {
                check_device($device, undef, \$os_drive, \@pools);
            };
            if ($@) {
                output_error("Error checking device: $@");
                return @pools;
            }
        }
    }
    
    return @pools;
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

# Utility function to check current pool status using rtStatus.pl
# Returns decoded JSON status information or undef on failure
sub check_pool_status {
    my $script_dir = $0;
    $script_dir =~ s/[^\/]+$//;
    my $status_script = "${script_dir}rtStatus.pl";
    
    my $status_output = `$status_script -j`;
    if ($? == 0) {
        my $status = decode_json($status_output);
        return $status;
    }
    return undef;
}

# Utility function to check if a pool is already imported
# Returns 1 if pool is imported, 0 otherwise
sub is_pool_already_imported {
    my ($pool_name) = @_;
    my $status = check_pool_status();
    
    if ($status && $status->{imported_pools}) {
        foreach my $pool (@{$status->{imported_pools}}) {
            return 1 if $pool->{name} eq $pool_name;
        }
    }
    return 0;
}

# Handle ZFS pool import operations
if ($command eq 'import') {
    write_log("Starting pool import operation");
    if ($device_path) {
        write_log("Import mode: specific device ($device_path)");
        # Import pool from specific device
        output_message("Checking device $device_path for pools...", 1);
        write_log("Executing: zpool import -d $device_path");
        my $import_output = `zpool import -d $device_path 2>&1`;
        write_log("Import scan output: $import_output");
        
        if ($import_output =~ /pool:\s+(\S+)/m) {
            my $pool_name = $1;
            write_log("Found pool: $pool_name on device $device_path");
            
            # Check if this is an RT pool or if we should import all
            unless (is_rt_pool($pool_name) || $ENV{RT_EXPORT_ALL}) {
                write_log("Skipping non-RT pool: $pool_name");
                output_message("Skipping non-RT pool: $pool_name (set RT_EXPORT_ALL=1 to import all pools)", 0);
                exit 0;
            }
            
            # Prevent duplicate imports
            if (is_pool_already_imported($pool_name)) {
                write_log("Pool $pool_name is already imported");
                output_message("Pool $pool_name is already imported", 1);
                exit 0;
            }
            
            output_message("Found pool: $pool_name", 1);
            
            # Show detailed pool status in non-JSON mode
            if (!$json_output) {
                print "Pool status:\n$import_output\n";
            }
            
            # Attempt standard import first
            write_log("Attempting standard import of pool: $pool_name");
            output_message("Attempting to import pool...", 1);
            $import_output = `zpool import -f -d $device_path $pool_name 2>&1`;
            my $import_exit_code = $? >> 8;
            write_log("Standard import exit code: $import_exit_code");
            write_log("Standard import output: $import_output");
            
            if ($import_exit_code == 0) {
                write_log("Standard import successful");
                output_message("Successfully imported pool $pool_name", 1);
            } else {
                # If standard import fails, try force recovery
                write_log("Standard import failed, attempting force recovery");
                output_message("Standard import failed, attempting force recovery...", 0);
                $import_output = `zpool import -F -f -d $device_path $pool_name 2>&1`;
                $import_exit_code = $? >> 8;
                write_log("Force recovery exit code: $import_exit_code");
                write_log("Force recovery output: $import_output");
                
                if ($import_exit_code == 0) {
                    write_log("Force recovery import successful");
                    output_message("Successfully imported pool $pool_name using force recovery", 1);
                } else {
                    log_error("Both standard and force recovery import failed");
                    output_error("Failed to import pool $pool_name: $import_output");
                }
            }
        } else {
            log_error("No importable pool found on $device_path");
            output_error("No importable pool found on $device_path");
        }
    } else {
        write_log("Import mode: auto-detect all available pools");
        # Auto-detect and import all available pools
        
        # Get current pool status for comparison
        my $status = check_pool_status();
        if (!$status) {
            output_error("Failed to get current pool status");
        }
        
        # Scan for available pools
        my $import_output = `zpool import 2>&1`;
        my @pools;
        my $results = [];
        my $success = 0;
        
        # Parse output to identify available pools
        while ($import_output =~ /pool:\s+(\S+).*?config:.*?\n\s+(\S+)\s+ONLINE/gs) {
            my $pool_name = $1;
            my $device = $2;
            
            # Skip pools that are already imported
            next if is_pool_already_imported($pool_name);
            
            # Skip non-RT pools unless RT_EXPORT_ALL is set
            unless (is_rt_pool($pool_name) || $ENV{RT_EXPORT_ALL}) {
                unless ($json_output) {
                    print "Skipping non-RT pool: $pool_name (set RT_EXPORT_ALL=1 to import all pools)\n";
                }
                next;
            }
            
            push @pools, { 
                name => $pool_name, 
                device => $device,
                is_rt_pool => is_rt_pool($pool_name) ? 1 : 0 
            };
        }
        
        if (@pools) {
            # Process each discovered pool
            foreach my $pool (@pools) {
                my $pool_result = {
                    pool => $pool->{name},
                    device => $pool->{device},
                    is_rt_pool => $pool->{is_rt_pool} ? JSON::true : JSON::false,
                    success => JSON::false
                };
                
                # Show progress in non-JSON mode
                output_message("Found pool: $pool->{name} on device $pool->{device}", 1) unless $json_output;
                output_message("Attempting to import pool...", 1) unless $json_output;
                
                # Attempt standard import first
                my $result = `zpool import -f $pool->{name} 2>&1`;
                if ($? == 0) {
                    $pool_result->{success} = JSON::true;
                    $pool_result->{message} = "Successfully imported";
                    $success = 1;
                    output_message("Successfully imported pool $pool->{name}", 1) unless $json_output;
                } else {
                    # If standard import fails, try force recovery
                    output_message("Standard import failed, attempting force recovery...", 0) unless $json_output;
                    $result = `zpool import -F -f $pool->{name} 2>&1`;
                    if ($? == 0) {
                        $pool_result->{success} = JSON::true;
                        $pool_result->{message} = "Successfully imported using force recovery";
                        $success = 1;
                        output_message("Successfully imported pool $pool->{name} using force recovery", 1) unless $json_output;
                    } else {
                        $pool_result->{success} = JSON::false;
                        $pool_result->{message} = "Failed to import: $result";
                        output_message("Failed to import pool $pool->{name}: $result", 0) unless $json_output;
                    }
                }
                push @$results, $pool_result;
            }
            
            # Output final results in JSON format if requested
            if ($json_output) {
                print encode_json({
                    success => $success,
                    pools => $results
                }) . "\n";
            }
        } else {
            output_error("No importable ZFS pools found or all pools are already imported");
        }
    }
}
# Handle ZFS pool export operations
elsif ($command eq 'export') {
    write_log("Starting pool export operation");
    my $results = [];
    
    if ($device_path) {
        write_log("Export mode: specific device ($device_path)");
        # Export pool from specific device
        
        # Get pool name associated with device
        write_log("Finding pool associated with device: $device_path");
        my $pool_name = `zpool list -H -o name -d $device_path 2>/dev/null`;
        chomp($pool_name);
        write_log("Pool found for device: " . ($pool_name || 'none'));
        
        if ($pool_name) {
            # Check if this is an RT pool or if we should export all
            if (is_rt_pool($pool_name) || $ENV{RT_EXPORT_ALL}) {
                write_log("Attempting to export pool: $pool_name");
                # Attempt to export the pool
                my $result = `zpool export $pool_name 2>&1`;
                my $success = $? == 0;
                my $message = $success ? "Successfully exported pool $pool_name" : "Failed to export pool $pool_name: $result";
                
                write_log("Export result (success=$success): $message");
                
                # Output results in requested format
                if ($json_output) {
                    print encode_json({
                        success => $success,
                        pool => $pool_name,
                        message => $message
                    }) . "\n";
                } else {
                    print "$message\n";
                }
                die $message unless $success;
            } else {
                write_log("Skipping non-RT pool: $pool_name");
                output_message("Skipping non-RT pool: $pool_name (set RT_EXPORT_ALL=1 to export all pools)", 0);
            }
        } else {
            log_error("No active ZFS pool found on $device_path");
            output_error("No active ZFS pool found on $device_path");
        }
    } else {
        write_log("Export mode: all pools except system pool");
        # Export all pools except the system root pool
        my $pools = `zpool list -H -o name`;
        write_log("Available pools: $pools");
        
        for my $pool (split /\n/, $pools) {
            write_log("Processing pool for export: $pool");
            # Skip the root pool for system safety
            next if $pool eq 'rpool';
            
            # Skip non-RT pools unless RT_EXPORT_ALL is set
            unless (is_rt_pool($pool) || $ENV{RT_EXPORT_ALL}) {
                write_log("Skipping non-RT pool: $pool");
                unless ($json_output) {
                    print "Skipping non-RT pool: $pool (set RT_EXPORT_ALL=1 to export all pools)\n";
                }
                next;
            }
            
            # Attempt to export each pool
            write_log("Attempting to export pool: $pool");
            my $result = `zpool export $pool 2>&1`;
            my $success = $? == 0;
            write_log("Export result for $pool (success=$success): $result");
            
            my $pool_result = {
                pool => $pool,
                success => $success,
                message => $success ? "Successfully exported" : "Failed to export: $result",
                is_rt_pool => is_rt_pool($pool) ? JSON::true : JSON::false
            };
            push @$results, $pool_result;
            
            # Show progress in non-JSON mode
            unless ($json_output) {
                print($success ? "Successfully exported pool $pool\n" : "Failed to export pool $pool: $result\n");
            }
        }
        
        write_log("Export operation completed for " . scalar(@$results) . " pools");
        
        # Output final results in JSON format if requested
        if ($json_output) {
            print encode_json({
                success => 1,
                pools => $results
            }) . "\n";
        }
    }
}

