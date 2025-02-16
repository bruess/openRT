#!/usr/bin/perl
use strict;
use warnings;
use File::Find;
use File::Basename;
use Cwd 'abs_path';
use Getopt::Long;

# Command line options
my $json_only = 0;
GetOptions('j|json' => \$json_only) or die "Usage: $0 [-j]\n";

# Global variables for cleanup
my $agents_dataset;
my $temp_mount;
my $cleanup_needed = 0;

# Cleanup function
sub cleanup {
    return unless $cleanup_needed;
    
    unless ($json_only) {
        print "\nPerforming cleanup...\n";
    }
    
    if ($agents_dataset) {
        unless ($json_only) {
            print "Unmounting all agent datasets...\n";
        }
        my @datasets = `zfs list -H -o name -r $agents_dataset 2>/dev/null`;
        chomp(@datasets);
        foreach my $dataset (reverse @datasets) {
            system("zfs unmount $dataset 2>/dev/null");
            system("zfs set mountpoint=none $dataset 2>/dev/null");
        }
    }
    
    if ($temp_mount && -d $temp_mount) {
        unless ($json_only) {
            print "Removing temporary mount directory...\n";
        }
        system("rmdir $temp_mount 2>/dev/null");
    }
    
    $cleanup_needed = 0;
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

# Function to find RT pool name
sub find_rt_pool {
    my @pools = `zpool list -H -o name`;
    chomp(@pools);
    foreach my $pool (@pools) {
        return $pool if $pool =~ /^rtPool-\d+$/;
    }
    return undef;
}

# Get RT pool name
my $rt_pool = find_rt_pool();
die "No RT pool found. Please ensure the RT drive is connected and imported.\n" unless $rt_pool;
print "Found RT pool: $rt_pool\n" unless $json_only;

# Check RT pool status using rtStatus.pl
my $status_script = "$script_dir/rtStatus.pl";
die "Cannot find rtStatus.pl at $status_script\n" unless -f $status_script;

print "Checking RT pool status...\n" unless $json_only;
my $status_check = `perl "$status_script" -j`;
my $status_result;
eval {
    $status_result = decode_json($status_check);
};
if ($@) {
    die "Failed to parse rtStatus.pl output: $status_check\n";
}

# Verify pool is in correct state
unless ($status_result && $status_result->{status} eq "Imported") {
    my $msg = "RT pool is not in the correct state. Current status: " . ($status_result ? $status_result->{status} : "Unknown") . "\n";
    $msg .= "Please ensure the RT drive is connected and the pool is imported.\n";
    die $msg;
}

print "RT pool is imported. Proceeding with metadata collection...\n" unless $json_only;

# Get the agents dataset name
$agents_dataset = "$rt_pool/home/agents";
my $agents_info = `zfs list -H -o name,mountpoint "$agents_dataset" 2>&1`;
if ($? != 0) {
    die "Agents dataset ($agents_dataset) does not exist in the RT pool.\n";
}

# Create a temporary mount directory
$temp_mount = "/tmp/rt_metadata_$$";  # Using PID to make it unique
system("mkdir -p $temp_mount") == 0
    or die "Failed to create temporary mount directory: $?\n";

$cleanup_needed = 1;  # Mark that cleanup will be needed
print "Setting up temporary mount point at $temp_mount\n" unless $json_only;

# First unmount all datasets
print "Unmounting all agent datasets...\n" unless $json_only;
my @agent_datasets = `zfs list -H -o name -r $agents_dataset`;
chomp(@agent_datasets);
foreach my $dataset (reverse @agent_datasets) {  # Unmount in reverse order
    system("zfs unmount $dataset 2>/dev/null");
}

# Set mountpoints and mount datasets
print "Setting mountpoints and mounting datasets...\n" unless $json_only;
foreach my $dataset (@agent_datasets) {
    my $relative_path = $dataset;
    $relative_path =~ s/^$agents_dataset\/?//;  # Remove parent dataset prefix
    my $mount_path = $relative_path ? "$temp_mount/$relative_path" : $temp_mount;
    
    print "Setting mountpoint for $dataset to $mount_path\n" unless $json_only;
    system("mkdir -p $mount_path 2>/dev/null");
    if ($json_only) {
        system("zfs set mountpoint=$mount_path $dataset >/dev/null 2>&1");
        system("zfs mount $dataset >/dev/null 2>&1");
    } else {
        system("zfs set mountpoint=$mount_path $dataset") == 0
            or warn "Failed to set mountpoint for $dataset: $?\n";
        system("zfs mount $dataset") == 0
            or warn "Failed to mount $dataset: $?\n";
    }
}

# Initialize metadata storage
my %agent_metadata;

# Function to process agentInfo files
sub process_agent_info {
    my $file = $_;
    return unless $file =~ /\.agentInfo$/;  # Match any file ending in .agentInfo
    
    my $dir = $File::Find::dir;
    my $full_path = $File::Find::name;
    
    print "Processing agent info: $full_path\n" unless $json_only;
    
    # Read and parse agentInfo file
    open(my $fh, '<', $full_path) or warn "Cannot open $full_path: $!\n" and return;
    my $content = do { local $/; <$fh> };
    close($fh);

    # Try to parse PHP serialized data
    my $agent_info;
    eval {
        $agent_info = PHP::Serialization::unserialize($content);
    };
    if ($@) {
        warn "Failed to parse PHP serialized data in $full_path: $@\n";
        return;
    }

    # Extract agent ID from path
    my $agent_id;
    if ($dir =~ m{/([^/]+)$}) {  # Extract last directory component
        $agent_id = $1;
    } else {
        warn "Could not extract agent ID from path: $dir\n";
        return;
    }

    # Add additional metadata
    $agent_info->{agentId} = $agent_id;
    $agent_info->{agentInfoFile} = basename($full_path);
    
    # Store metadata
    $agent_metadata{$agent_id} = $agent_info;
    print "Added metadata for agent: $agent_id\n" unless $json_only;
}

# Find and process all agentInfo files
print "Searching for agent info files in $temp_mount...\n" unless $json_only;
find(\&process_agent_info, $temp_mount);

# Output the complete metadata as JSON
my $output = {
    success => JSON::true,
    timestamp => time(),
    pool_name => $rt_pool,
    agents_path => $temp_mount,
    agent_count => scalar(keys %agent_metadata),
    agents => \%agent_metadata
};

unless ($json_only) {
    print "\nMetadata collection complete. Found " . scalar(keys %agent_metadata) . " agents.\n";
}

# Create JSON encoder with pretty printing for -j option
my $json = JSON->new->utf8;
$json->pretty(1) if $json_only;
print $json->encode($output) . "\n";

# Cleanup is handled automatically by END block
