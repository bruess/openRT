#!/usr/bin/perl
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

# Check if running as root
die "This script must be run as root\n" unless $> == 0;

# Process command line arguments
my $json_output = 0;
my $command = '';
my $device_path = '';

# First pass: look for command and device path
foreach my $arg (@ARGV) {
    next if $arg eq '-j';
    if (!$command && $arg =~ /^(import|export)$/) {
        $command = $arg;
    } elsif (!$device_path) {
        $device_path = $arg;
    }
}

# Second pass: check for -j flag
$json_output = grep { $_ eq '-j' } @ARGV;

# Validate command
unless ($command =~ /^(import|export)$/) {
    my $error = {
        error => "Invalid command",
        usage => "$0 [import|export] [device_path] [-j]"
    };
    die($json_output ? encode_json($error) . "\n" : "Usage: $0 [import|export] [device_path] [-j]\n");
}

# Function to check if a pool is an RT pool
sub is_rt_pool {
    my ($pool_name) = @_;
    
    # Define standard RT pool patterns
    my @rt_patterns = (
        qr/^rtPool-\d+$/,  # Original pattern
        qr/^revRT/         # New pattern
    );
    
    # Check for custom pattern from environment variable
    if ($ENV{RT_POOL_PATTERN}) {
        my $custom_pattern = $ENV{RT_POOL_PATTERN};
        unshift @rt_patterns, qr/$custom_pattern/;
    }
    
    # If a specific pool name is set, check for exact match
    if ($ENV{RT_POOL_NAME} && $pool_name eq $ENV{RT_POOL_NAME}) {
        return 1;
    }
    
    # Check against patterns
    foreach my $pattern (@rt_patterns) {
        return 1 if $pool_name =~ $pattern;
    }
    
    return 0;
}

# Output functions
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

sub output_error {
    my ($message) = @_;
    my $error = {
        success => JSON::false,
        error => $message
    };
    die($json_output ? encode_json($error) . "\n" : "$message\n");
}

# Function to get OS drive
sub get_os_drive {
    my $os_drive = `mount | grep ' / ' | cut -d' ' -f1`;
    $os_drive =~ s/\d+$//; # Remove partition number
    chomp($os_drive);
    return $os_drive;
}

# Function to get detailed pool status
sub get_pool_status {
    my ($device, $pool_name) = @_;
    my $status = `zpool import -d $device $pool_name 2>&1`;
    return $status;
}

# Function to find importable ZFS pools
sub find_importable_pools {
    my @pools;
    my $os_drive = get_os_drive();
    
    # Get list of block devices and partitions in JSON format
    my $lsblk_json = `lsblk -J -o NAME,TYPE,PKNAME,SIZE,MOUNTPOINT`;
    my $devices = decode_json($lsblk_json);
    
    sub check_device {
        my ($device, $parent_name) = @_;
        my $dev_name = $device->{name};
        my $dev_type = $device->{type};
        my $mount = $device->{mountpoint} || '';
        
        # Skip if this is the OS drive or its partitions
        return if $mount eq '/' || $mount =~ m{^/boot};
        return if defined $parent_name && "/dev/$parent_name" eq $os_drive;
        return if "/dev/$dev_name" eq $os_drive;
        
        # Form full device path
        my $dev_path = "/dev/$dev_name";
        
        # Check if device has importable ZFS pools
        print "Checking $dev_type $dev_path (Size: $device->{size})\n";
        my $zpool_output = `zpool import -d $dev_path 2>/dev/null`;
        if ($? == 0 && $zpool_output =~ /pool:\s+(\S+)/m) {
            my $pool_name = $1;
            
            # Skip if not an RT pool unless a specific pool name is set
            if (!is_rt_pool($pool_name) && !$ENV{RT_POOL_NAME}) {
                print "Found pool $pool_name but it doesn't match RT pool patterns. Skipping.\n" unless $json_output;
                return;
            }
            
            my $status = get_pool_status($dev_path, $pool_name);
            
            if ($status =~ /pool:\s+(\S+).*?state:\s+(\S+)/s) {
                push @pools, { 
                    device => $dev_path, 
                    pool => $1,
                    state => $2,
                    status => $status,
                    type => $dev_type,
                    size => $device->{size},
                    is_rt_pool => is_rt_pool($1) ? JSON::true : JSON::false
                };
            }
        }
        
        # Recursively check children
        if ($device->{children}) {
            foreach my $child (@{$device->{children}}) {
                check_device($child, $dev_name);
            }
        }
    }
    
    # Check all devices
    foreach my $device (@{$devices->{blockdevices}}) {
        check_device($device);
    }
    
    return @pools;
}

# Function to check pool status using rtStatus.pl
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

# Function to check if pool is already imported
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

# Handle import
if ($command eq 'import') {
    if ($device_path) {
        # Import from specific device
        output_message("Checking device $device_path for pools...", 1);
        my $import_output = `zpool import -d $device_path 2>&1`;
        if ($import_output =~ /pool:\s+(\S+)/m) {
            my $pool_name = $1;
            
            # Check if pool is already imported
            if (is_pool_already_imported($pool_name)) {
                output_message("Pool $pool_name is already imported", 1);
                exit 0;
            }
            
            output_message("Found pool: $pool_name", 1);
            
            if (!$json_output) {
                print "Pool status:\n$import_output\n";
            }
            
            output_message("Attempting to import pool...", 1);
            $import_output = `zpool import -f -d $device_path $pool_name 2>&1`;
            if ($? == 0) {
                output_message("Successfully imported pool $pool_name", 1);
            } else {
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
        # Get current status
        my $status = check_pool_status();
        if (!$status) {
            output_error("Failed to get current pool status");
        }
        
        # Auto-detect and import all available pools
        my $import_output = `zpool import 2>&1`;
        my @pools;
        my $results = [];
        
        # Parse the output to find all available pools
        while ($import_output =~ /pool:\s+(\S+).*?config:.*?\n\s+(\S+)\s+ONLINE/gs) {
            my $pool_name = $1;
            my $device = $2;
            
            # Skip if pool is already imported
            next if is_pool_already_imported($pool_name);
            
            push @pools, { name => $pool_name, device => $device };
        }
        
        if (@pools) {
            foreach my $pool (@pools) {
                my $pool_result = {
                    pool => $pool->{name},
                    device => $pool->{device},
                    success => JSON::false
                };
                
                output_message("\nFound pool: $pool->{name} on device $pool->{device}", 1);
                output_message("Attempting to import pool...", 1);
                
                my $result = `zpool import -f $pool->{name} 2>&1`;
                if ($? == 0) {
                    $pool_result->{success} = JSON::true;
                    $pool_result->{message} = "Successfully imported";
                    output_message("Successfully imported pool $pool->{name}", 1);
                } else {
                    output_message("Standard import failed, attempting force recovery...", 0);
                    $result = `zpool import -F -f $pool->{name} 2>&1`;
                    if ($? == 0) {
                        $pool_result->{success} = JSON::true;
                        $pool_result->{message} = "Successfully imported using force recovery";
                        output_message("Successfully imported pool $pool->{name} using force recovery", 1);
                    } else {
                        $pool_result->{success} = JSON::false;
                        $pool_result->{message} = "Failed to import: $result";
                        output_message("Failed to import pool $pool->{name}: $result", 0);
                    }
                }
                push @$results, $pool_result;
            }
            
            if ($json_output) {
                print encode_json({
                    success => 1,
                    pools => $results
                }) . "\n";
            }
        } else {
            output_error("No importable ZFS pools found or all pools are already imported");
        }
    }
}
# Handle export
elsif ($command eq 'export') {
    my $results = [];
    
    if ($device_path) {
        # Get pool name from device
        my $pool_name = `zpool list -H -o name -d $device_path 2>/dev/null`;
        chomp($pool_name);
        if ($pool_name) {
            my $result = `zpool export $pool_name 2>&1`;
            my $success = $? == 0;
            my $message = $success ? "Successfully exported pool $pool_name" : "Failed to export pool $pool_name: $result";
            
            if ($json_output) {
                print encode_json({
                    success => $success,
                    pool => $pool_name,
                    message => $message,
                    is_rt_pool => is_rt_pool($pool_name) ? JSON::true : JSON::false
                }) . "\n";
            } else {
                print "$message\n";
            }
            die $message unless $success;
        } else {
            output_error("No active ZFS pool found on $device_path");
        }
    } else {
        # Export all pools except the root pool
        my $pools = `zpool list -H -o name`;
        for my $pool (split /\n/, $pools) {
            next if $pool eq 'rpool'; # Skip root pool
            
            # Skip if not an RT pool, unless RT_EXPORT_ALL is set
            if (!is_rt_pool($pool) && !$ENV{RT_EXPORT_ALL}) {
                output_message("Skipping non-RT pool $pool", 1) unless $json_output;
                next;
            }
            
            my $result = `zpool export $pool 2>&1`;
            my $success = $? == 0;
            my $pool_result = {
                pool => $pool,
                success => $success,
                message => $success ? "Successfully exported" : "Failed to export: $result",
                is_rt_pool => is_rt_pool($pool) ? JSON::true : JSON::false
            };
            push @$results, $pool_result;
            
            unless ($json_output) {
                print($success ? "Successfully exported pool $pool\n" : "Failed to export pool $pool: $result\n");
            }
        }
        
        if ($json_output) {
            print encode_json({
                success => 1,
                pools => $results
            }) . "\n";
        }
    }
}

