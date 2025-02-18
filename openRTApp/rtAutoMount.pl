#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use File::Path qw(make_path);
use POSIX qw(strftime);
use Fcntl qw(:flock);
use File::Basename;
use Cwd 'abs_path';

# Get script directory
my $script_dir = dirname(abs_path($0));

# Constants
my $STATUS_DIR = "/usr/local/openRT/status";
my $LOCK_FILE = "$STATUS_DIR/automount.lock";
my $STATUS_FILE = "$STATUS_DIR/automount_status.json";
my $AUTOMOUNT_FLAG = "$STATUS_DIR/automount";

# Check if automount is enabled
exit 0 unless -f $AUTOMOUNT_FLAG && trim(read_file($AUTOMOUNT_FLAG)) eq '1';

# Try to get lock
open(my $lock_fh, '>', $LOCK_FILE) or die "Cannot open lock file: $!\n";
unless (flock($lock_fh, LOCK_EX | LOCK_NB)) {
    print "Another instance is already running\n";
    exit 0;
}

# Initialize status
my $status = {
    running => JSON::true,
    start_time => time(),
    current_step => "Starting automount process",
    progress => 0,
    total_steps => 0,
    completed_steps => 0,
    details => [],
    error => undef
};
update_status();

# Cleanup handler
END {
    if ($lock_fh) {
        $status->{running} = JSON::false;
        $status->{end_time} = time();
        update_status();
        flock($lock_fh, LOCK_UN);
        close($lock_fh);
        unlink($LOCK_FILE);
    }
}

# Helper function to read file content
sub read_file {
    my ($file) = @_;
    open(my $fh, '<', $file) or return "";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

# Helper function to trim whitespace
sub trim {
    my ($str) = @_;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

# Update status file
sub update_status {
    open(my $status_fh, '>', $STATUS_FILE) or die "Cannot open status file: $!\n";
    print $status_fh encode_json($status);
    close($status_fh);
}

# Add a detail message and update progress
sub add_detail {
    my ($message) = @_;
    push @{$status->{details}}, {
        time => time(),
        message => $message
    };
    $status->{completed_steps}++;
    $status->{progress} = int(($status->{completed_steps} / $status->{total_steps}) * 100);
    update_status();
}

# Function to handle errors
sub handle_error {
    my ($error) = @_;
    $status->{error} = $error;
    add_detail("Error: $error");
    die "$error\n";
}

# Check if running as root
die "This script must be run as root\n" unless $> == 0;

# Get pool status
$status->{current_step} = "Checking pool status";
update_status();

my $status_script = "$script_dir/rtStatus.pl";
my $status_output = `perl "$status_script" -j`;
my $pool_status;
eval {
    $pool_status = decode_json($status_output);
};
handle_error("Failed to get pool status: $@") if $@;

# Check if pool is available
unless ($pool_status->{status} eq "Available") {
    add_detail("Pool is not available for import");
    exit 0;
}

# Calculate total steps (1 for pool import + 1 for metadata + 1 per agent)
$status->{total_steps} = 3; # Base steps
update_status();

# Import pool using rtImport.pl
$status->{current_step} = "Importing pool";
update_status();

my $import_script = "$script_dir/rtImport.pl";
system("perl", $import_script, "import");

# Verify import using rtStatus.pl
my $status_script = "$script_dir/rtStatus.pl";
my $status_output = `perl "$status_script" -j`;
my $pool_status;

eval {
    $pool_status = decode_json($status_output);
};

if ($@ || !$pool_status) {
    handle_error("Failed to verify pool status: $@");
}

# Check if pool is imported by looking at the status
if ($pool_status->{status} eq "Imported") {
    add_detail("Pool imported successfully");
} else {
    handle_error("Failed to import pool: Pool status is " . $pool_status->{status});
}

# Get metadata
$status->{current_step} = "Getting agent metadata";
update_status();

my $metadata_script = "$script_dir/rtMetadata.pl";
my $metadata_output = `perl "$metadata_script" -j`;

# First attempt might trigger module installation
if ($metadata_output =~ /Required modules not found/i) {
    # Wait a moment for installation to complete
    sleep(12);
    # Try again after modules are installed
    $metadata_output = `perl "$metadata_script" -j`;
}

my $metadata;
eval {
    $metadata = decode_json($metadata_output);
};
handle_error("Failed to get metadata: $@") if $@;
add_detail("Retrieved metadata for " . $metadata->{agent_count} . " agents");

# Update total steps with actual agent count
$status->{total_steps} += $metadata->{agent_count};
update_status();

# Mount each agent
$status->{current_step} = "Mounting agents";
update_status();





my $mount_script = "$script_dir/rtFileMount.pl";

system("perl", $mount_script, "cleanup"); # Clean up any existing mounts before starting




foreach my $agent_id (keys %{$metadata->{agents}}) {
    my $agent_info = $metadata->{agents}->{$agent_id};
    my $agent_name = $agent_info->{hostname} || $agent_info->{name} || $agent_id;
    
    add_detail("Mounting agent: $agent_name");
    
    # Clean up any existing mounts for this agent
   
   #system("perl", $mount_script, "-cleanup=$agent_id");
    
    # Mount all snapshots for the agent
    my $mount_output = `perl "$mount_script" -j "$agent_id" all 2>&1`;
    my $mount_result;
    eval {
        $mount_result = decode_json($mount_output);
    };
    if ($@ || !$mount_result->{status} eq "success") {
        add_detail("Warning: Failed to mount agent $agent_name: " . ($@ || $mount_output));
        next;
    }
    
    add_detail("Successfully mounted agent: $agent_name");
}

$status->{current_step} = "Completed";
add_detail("Automount process completed successfully"); 