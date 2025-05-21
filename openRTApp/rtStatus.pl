#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw(strftime);

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

# Process command line arguments
my $json_output = grep { $_ eq '-j' } @ARGV;

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

# Function to check if any non-OS drives are connected
sub check_drives {
    my @drives = `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT -n`;
    my $has_extra_drives = 0;
    my @extra_drives;
    
    foreach my $drive (@drives) {
        if ($drive =~ /sd[b-z]/ && $drive =~ /disk/) {
            $has_extra_drives = 1;
            if ($drive =~ /(\S+)\s+(\S+)\s+(\S+)/) {
                push @extra_drives, {
                    name => $1,
                    size => $2,
                    type => $3
                };
            }
        }
    }
    return ($has_extra_drives, \@extra_drives);
}

# Function to check ZFS pools
sub check_zfs_pools {
    my @pools = `zpool list -H`;
    my $has_imported_pool = 0;
    my $has_available_pool = 0;
    my @imported_pools;
    my @available_pools;
    
    # Check for available but not imported pools
    my $import_output = `zpool import 2>&1`;
    while ($import_output =~ /pool:\s+(\S+).*?state:\s+(\S+)/gs) {
        my $pool_name = $1;
        my $is_rt = is_rt_pool($pool_name);
        $has_available_pool = 1 if $is_rt;
        
        push @available_pools, {
            name => $pool_name,
            state => $2,
            is_rt_pool => $is_rt ? JSON::true : JSON::false
        };
    }
    
    # Check for imported pools
    if ($? == 0 && @pools) {
        foreach my $pool (@pools) {
            if ($pool =~ /^(\S+)\s+(\S+)\s+(\S+)/) {
                my $pool_name = $1;
                my $is_rt = is_rt_pool($pool_name);
                $has_imported_pool = 1 if $is_rt;
                
                push @imported_pools, {
                    name => $pool_name,
                    size => $2,
                    allocated => $3,
                    is_rt_pool => $is_rt ? JSON::true : JSON::false
                };
            }
        }
    }
    
    return ($has_imported_pool, $has_available_pool, \@imported_pools, \@available_pools);
}

# Main status check
sub get_rt_status {
    my ($has_drives, $extra_drives) = check_drives();
    my ($has_imported_pool, $has_available_pool, $imported_pools, $available_pools) = check_zfs_pools();
    
    my $status = "Not Available";
    if ($has_imported_pool) {
        $status = "Imported";
    } elsif ($has_available_pool) {
        $status = "Available";
    } elsif (!$has_drives) {
        $status = "Not Available";
    }
    
    if ($json_output) {
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
        print "$status\n";
    }
}

# Get and print the status
get_rt_status();

exit 0;


