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
# NOTES:
#   - Excludes OS drive from drive detection
#   - Supports both standalone and integrated usage
#   - Used by other OpenRT scripts for system validation
#
###############################################################################

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

# Constants for GitHub updates
my $GITHUB_UPDATE_FLAG = "/var/run/openrt_github_update.flag";
my $GITHUB_UPDATE_SCRIPT = "/usr/local/openRT/setup/githubUpdates.sh";

# Function to check if GitHub update should run
# Returns: Boolean indicating if update should run
sub should_run_github_update {
    # Get system boot time using built-in stat
    my @proc_stat = stat("/proc/1");
    return 1 unless @proc_stat; # Run if we can't get boot time
    my $boot_time = $proc_stat[9];
    
    # Check if flag file exists
    if (-e $GITHUB_UPDATE_FLAG) {
        my @flag_stat = stat($GITHUB_UPDATE_FLAG);
        return 1 unless @flag_stat; # Run if we can't get flag time
        my $flag_time = $flag_stat[9];
        # Return true if flag is older than boot time
        return $flag_time < $boot_time;
    }
    
    # No flag file exists, should run
    return 1;
}

# Function to run GitHub update and create flag
sub run_github_update {
    if (-x $GITHUB_UPDATE_SCRIPT) {
        system("sudo $GITHUB_UPDATE_SCRIPT");
        # Create/update flag file
        system("touch $GITHUB_UPDATE_FLAG");
    }
}

# Function to check for connected non-OS drives
# Returns: ($has_extra_drives, \@extra_drives)
#   - $has_extra_drives: Boolean indicating if non-OS drives are present
#   - @extra_drives: Array of hashes containing drive details (name, size, type)
sub check_drives {
    my @drives = `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT -n`;
    my $has_extra_drives = 0;
    my @extra_drives;
    
    foreach my $drive (@drives) {
        # Look for any drive except sda (assumed OS drive)
        if ($drive =~ /sd[a-z]/ && $drive =~ /disk/) {
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

# Function to check ZFS pool status
# Returns: ($has_imported_pool, $has_available_pool, \@imported_pools, \@available_pools)
#   - $has_imported_pool: Boolean indicating if any pools are imported
#   - $has_available_pool: Boolean indicating if any pools are available
#   - @imported_pools: Array of hashes with imported pool details
#   - @available_pools: Array of hashes with available pool details
sub check_zfs_pools {
    my @pools = `zpool list -H`;
    my $has_imported_pool = 0;
    my $has_available_pool = 0;
    my @imported_pools;
    my @available_pools;
    
    # Check for available but not imported pools
    my $import_output = `zpool import 2>&1`;
    while ($import_output =~ /pool:\s+(\S+).*?state:\s+(\S+)/gs) {
        $has_available_pool = 1;
        push @available_pools, {
            name => $1,
            state => $2
        };
    }
    
    # Check currently imported pools
    if ($? == 0 && @pools) {
        $has_imported_pool = 1;
        foreach my $pool (@pools) {
            if ($pool =~ /^(\S+)\s+(\S+)\s+(\S+)/) {
                push @imported_pools, {
                    name => $1,
                    size => $2,
                    allocated => $3
                };
            }
        }
    }
    
    return ($has_imported_pool, $has_available_pool, \@imported_pools, \@available_pools);
}

# Main function to check and report system status
# Combines drive and pool checks to determine overall system state
sub get_rt_status {
    # Check and run GitHub updates if needed
    if (should_run_github_update()) {
        run_github_update();
    }
    
    # Check for connected drives
    my ($has_drives, $extra_drives) = check_drives();
    
    # Check ZFS pool status
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
    
    # Output results in requested format
    if ($json_output) {
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
        # Simple status output for human reading
        print "$status\n";
    }
}

# Execute status check and output results
get_rt_status();

exit 0;


