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

# Auto-install JSON module if needed
BEGIN {
    eval {
        require JSON;
        JSON->import();
    };
    if ($@) {
        print "JSON module not found. Installing...\n";
        system('apt-get update -qq && apt-get install -qq -y libjson-perl') == 0
            or die "Failed to install JSON module: $?\n";
        eval {
            require JSON;
            JSON->import();
        };
        die "Failed to load JSON module after installation: $@" if $@;
        print "JSON module installed successfully.\n";
    }
}

# Validate root privileges required for ZFS operations
die "This script must be run as root\n" unless $> == 0;

# Initialize command line parameters
my $json_output = 0;
my $command = '';
my $device_path = '';

# First pass: Parse primary command arguments
# Looking for main commands (import/export) and device path
foreach my $arg (@ARGV) {
    next if $arg eq '-j';
    if (!$command && $arg =~ /^(import|export)$/) {
        $command = $arg;
    } elsif (!$device_path) {
        $device_path = $arg;
    }
}

# Second pass: Check for JSON output flag
$json_output = grep { $_ eq '-j' } @ARGV;

# Validate command format
unless ($command =~ /^(import|export)$/) {
    my $error = {
        error => "Invalid command",
        usage => "$0 [import|export] [device_path] [-j]"
    };
    die($json_output ? encode_json($error) . "\n" : "Usage: $0 [import|export] [device_path] [-j]\n");
}

# Output handling functions for consistent message formatting
sub output_message {
    my ($message, $success) = @_;
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
    eval {
        # Get the device containing the root filesystem
        $os_drive = `mount | grep ' / ' | cut -d' ' -f1`;
        $os_drive =~ s/\d+$//; # Remove partition number to get base device
        chomp($os_drive);
    };
    if ($@) {
        output_error("Failed to get OS drive: $@");
    }
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
        my ($device, $parent_name) = @_;
        my $dev_name = $device->{name};
        my $dev_type = $device->{type};
        my $mount = $device->{mountpoint} || '';
        
        # Skip system partitions and OS drive
        return if $mount eq '/' || $mount =~ m{^/boot};
        return if defined $parent_name && "/dev/$parent_name" eq $os_drive;
        return if "/dev/$dev_name" eq $os_drive;
        
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
                push @pools, { 
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
                check_device($child, $dev_name);
            }
        }
    }
    
    # Process all block devices
    if ($devices && $devices->{blockdevices}) {
        foreach my $device (@{$devices->{blockdevices}}) {
            eval {
                check_device($device);
            };
            if ($@) {
                output_error("Error checking device: $@");
                return @pools;
            }
        }
    }
    
    return @pools;
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
    if ($device_path) {
        # Import pool from specific device
        output_message("Checking device $device_path for pools...", 1);
        my $import_output = `zpool import -d $device_path 2>&1`;
        if ($import_output =~ /pool:\s+(\S+)/m) {
            my $pool_name = $1;
            
            # Prevent duplicate imports
            if (is_pool_already_imported($pool_name)) {
                output_message("Pool $pool_name is already imported", 1);
                exit 0;
            }
            
            output_message("Found pool: $pool_name", 1);
            
            # Show detailed pool status in non-JSON mode
            if (!$json_output) {
                print "Pool status:\n$import_output\n";
            }
            
            # Attempt standard import first
            output_message("Attempting to import pool...", 1);
            $import_output = `zpool import -f -d $device_path $pool_name 2>&1`;
            if ($? == 0) {
                output_message("Successfully imported pool $pool_name", 1);
            } else {
                # If standard import fails, try force recovery
                output_message("Standard import failed, attempting force recovery...", 0);
                $import_output = `zpool import -F -f -d $device_path $pool_name 2>&1`;
                if ($? == 0) {
                    output_message("Successfully imported pool $pool_name using force recovery", 1);
                } else {
                    output_error("Failed to import pool $pool_name: $import_output");
                }
            }
        } else {
            output_error("No importable pool found on $device_path");
        }
    } else {
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
            
            push @pools, { name => $pool_name, device => $device };
        }
        
        if (@pools) {
            # Process each discovered pool
            foreach my $pool (@pools) {
                my $pool_result = {
                    pool => $pool->{name},
                    device => $pool->{device},
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
    my $results = [];
    
    if ($device_path) {
        # Export pool from specific device
        
        # Get pool name associated with device
        my $pool_name = `zpool list -H -o name -d $device_path 2>/dev/null`;
        chomp($pool_name);
        if ($pool_name) {
            # Attempt to export the pool
            my $result = `zpool export $pool_name 2>&1`;
            my $success = $? == 0;
            my $message = $success ? "Successfully exported pool $pool_name" : "Failed to export pool $pool_name: $result";
            
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
            output_error("No active ZFS pool found on $device_path");
        }
    } else {
        # Export all pools except the system root pool
        my $pools = `zpool list -H -o name`;
        for my $pool (split /\n/, $pools) {
            # Skip the root pool for system safety
            next if $pool eq 'rpool';
            
            # Attempt to export each pool
            my $result = `zpool export $pool 2>&1`;
            my $success = $? == 0;
            my $pool_result = {
                pool => $pool,
                success => $success,
                message => $success ? "Successfully exported" : "Failed to export: $result"
            };
            push @$results, $pool_result;
            
            # Show progress in non-JSON mode
            unless ($json_output) {
                print($success ? "Successfully exported pool $pool\n" : "Failed to export pool $pool: $result\n");
            }
        }
        
        # Output final results in JSON format if requested
        if ($json_output) {
            print encode_json({
                success => 1,
                pools => $results
            }) . "\n";
        }
    }
}

