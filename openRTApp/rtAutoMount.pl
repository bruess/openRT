#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use File::Path qw(make_path);
use POSIX qw(strftime);
use Fcntl qw(:flock);
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

# Get script directory
my $script_dir = dirname(abs_path($0));
write_log("Script directory: $script_dir");

# Constants
my $STATUS_DIR = "/usr/local/openRT/status";
my $LOCK_FILE = "$STATUS_DIR/automount.lock";
my $STATUS_FILE = "$STATUS_DIR/automount_status.json";
my $AUTOMOUNT_FLAG = "$STATUS_DIR/automount";

write_log("Status directory: $STATUS_DIR");
write_log("Lock file: $LOCK_FILE");
write_log("Status file: $STATUS_FILE");
write_log("Automount flag file: $AUTOMOUNT_FLAG");

# Check if automount is enabled
write_log("Checking if automount is enabled...");
if (!-f $AUTOMOUNT_FLAG) {
    write_log("Automount flag file does not exist, exiting");
    exit 0;
}

my $flag_content = trim(read_file($AUTOMOUNT_FLAG));
if ($flag_content ne '1') {
    write_log("Automount flag content is '$flag_content', not '1', exiting");
    exit 0;
}
write_log("Automount is enabled, proceeding...");

# Try to get lock
write_log("Attempting to acquire lock file: $LOCK_FILE");
if (!open(my $lock_fh, '>', $LOCK_FILE)) {
    log_error("Cannot open lock file: $!");
    die "Cannot open lock file: $!\n";
}

unless (flock($lock_fh, LOCK_EX | LOCK_NB)) {
    write_log("Another instance is already running, exiting gracefully");
    print "Another instance is already running\n";
    exit 0;
}
write_log("Lock acquired successfully");

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
write_log("Initializing status tracking");
update_status();

# Cleanup handler
END {
    if ($lock_fh) {
        write_log("Performing cleanup operations");
        $status->{running} = JSON::false;
        $status->{end_time} = time();
        update_status();
        flock($lock_fh, LOCK_UN);
        close($lock_fh);
        unlink($LOCK_FILE);
        write_log("Cleanup completed, lock file removed");
    }
}

# Helper function to read file content
sub read_file {
    my ($file) = @_;
    write_log("Reading file: $file");
    if (!open(my $fh, '<', $file)) {
        log_warning("Cannot open file $file: $!");
        return "";
    }
    my $content = do { local $/; <$fh> };
    close($fh);
    write_log("Successfully read " . length($content) . " bytes from $file");
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
    write_log("Updating status file: $STATUS_FILE");
    if (!open(my $status_fh, '>', $STATUS_FILE)) {
        log_error("Cannot open status file: $!");
        die "Cannot open status file: $!\n";
    }
    print $status_fh encode_json($status);
    close($status_fh);
    write_log("Status updated - Step: $status->{current_step}, Progress: $status->{progress}%");
}

# Add a detail message and update progress
sub add_detail {
    my ($message) = @_;
    write_log("Adding detail: $message");
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
    log_error("Handling error: $error");
    $status->{error} = $error;
    add_detail("Error: $error");
    die "$error\n";
}

# Check if running as root
write_log("Checking root privileges...");
if ($> != 0) {
    log_error("Script must be run as root (current UID: $>)");
    die "This script must be run as root\n";
}
write_log("Root privileges confirmed");

# Get pool status
write_log("Starting pool status check");
$status->{current_step} = "Checking pool status";
update_status();

my $status_script = "$script_dir/rtStatus.pl";
write_log("Using status script: $status_script");
my $status_output;

# Pass through environment variables if they exist
if (defined $ENV{RT_POOL_NAME} || defined $ENV{RT_POOL_PATTERN} || defined $ENV{RT_EXPORT_ALL} || defined $ENV{RT_AGENTS_PATH}) {
    write_log("Environment variables detected, using them for pool status check");
    write_log("RT_POOL_NAME: " . ($ENV{RT_POOL_NAME} // 'not set'));
    write_log("RT_POOL_PATTERN: " . ($ENV{RT_POOL_PATTERN} // 'not set'));
    write_log("RT_EXPORT_ALL: " . ($ENV{RT_EXPORT_ALL} // 'not set'));
    write_log("RT_AGENTS_PATH: " . ($ENV{RT_AGENTS_PATH} // 'not set'));
    $status_output = `perl "$status_script" -j`;
} else {
    write_log("No special environment variables set, using default pool detection");
    $status_output = `perl "$status_script" -j`;
}

write_log("Status script output: $status_output");

my $pool_status;
eval {
    $pool_status = decode_json($status_output);
};
if ($@) {
    handle_error("Failed to get pool status: $@");
}

write_log("Pool status parsed successfully");
write_log("Pool status: " . ($pool_status->{status} // 'unknown'));

# Check if pool is available
unless ($pool_status->{status} eq "Available") {
    write_log("Pool is not available for import (status: " . ($pool_status->{status} // 'unknown') . ")");
    add_detail("Pool is not available for import");
    exit 0;
}

write_log("Pool is available for import, proceeding...");

# Calculate total steps (1 for pool import + 1 for metadata + 1 per agent)
$status->{total_steps} = 3; # Base steps
write_log("Initial total steps set to: $status->{total_steps}");
update_status();

# Import pool using rtImport.pl
write_log("Starting pool import process");
$status->{current_step} = "Importing pool";
update_status();

my $import_script = "$script_dir/rtImport.pl";
write_log("Using import script: $import_script");
write_log("Executing: perl $import_script import");
system("perl", $import_script, "import");
my $import_exit_code = $? >> 8;
write_log("Import script exit code: $import_exit_code");

# Verify import using rtStatus.pl
write_log("Verifying pool import status");
$status_output = `perl "$status_script" -j`;
write_log("Post-import status output: $status_output");

eval {
    $pool_status = decode_json($status_output);
};

if ($@ || !$pool_status) {
    handle_error("Failed to verify pool status: $@");
}

# Check if pool is imported by looking at the status
if ($pool_status->{status} eq "Imported") {
    write_log("Pool import verification successful");
    add_detail("Pool imported successfully");
} else {
    handle_error("Failed to import pool: Pool status is " . $pool_status->{status});
}

# Get metadata
write_log("Starting metadata collection");
$status->{current_step} = "Getting agent metadata";
update_status();

my $metadata_script = "$script_dir/rtMetadata.pl";
write_log("Using metadata script: $metadata_script");
write_log("Executing: perl $metadata_script -j");
my $metadata_output = `perl "$metadata_script" -j`;
write_log("Initial metadata output length: " . length($metadata_output));

# First attempt might trigger module installation
if ($metadata_output =~ /Required modules not found/i) {
    write_log("Required modules not found, waiting for installation...");
    # Wait a moment for installation to complete
    sleep(12);
    # Try again after modules are installed
    write_log("Retrying metadata collection after module installation");
    $metadata_output = `perl "$metadata_script" -j`;
    write_log("Retry metadata output length: " . length($metadata_output));
}

my $metadata;
eval {
    $metadata = decode_json($metadata_output);
};
if ($@) {
    handle_error("Failed to get metadata: $@");
}

write_log("Metadata collection successful");
write_log("Agent count: " . ($metadata->{agent_count} // 0));
add_detail("Retrieved metadata for " . $metadata->{agent_count} . " agents");

# Update total steps with actual agent count
$status->{total_steps} += $metadata->{agent_count};
write_log("Updated total steps to: $status->{total_steps}");
update_status();

# Mount each agent
write_log("Starting agent mounting process");
$status->{current_step} = "Mounting agents";
update_status();

my $mount_script = "$script_dir/rtFileMount.pl";
write_log("Using mount script: $mount_script");

write_log("Performing cleanup of existing mounts");
system("perl", $mount_script, "cleanup"); # Clean up any existing mounts before starting

foreach my $agent_id (keys %{$metadata->{agents}}) {
    my $agent_info = $metadata->{agents}->{$agent_id};
    my $agent_name = $agent_info->{hostname} || $agent_info->{name} || $agent_id;
    
    write_log("Processing agent: $agent_name (ID: $agent_id)");
    add_detail("Mounting agent: $agent_name");
    
    # Mount all snapshots for the agent
    write_log("Executing mount command for agent $agent_name");
    my $mount_output = `perl "$mount_script" -j "$agent_id" all 2>&1`;
    write_log("Mount output for $agent_name: $mount_output");
    
    my $mount_result;
    eval {
        $mount_result = decode_json($mount_output);
    };
    if ($@ || !$mount_result->{status} eq "success") {
        log_warning("Failed to mount agent $agent_name: " . ($@ || $mount_output));
        add_detail("Warning: Failed to mount agent $agent_name: " . ($@ || $mount_output));
        next;
    }
    
    write_log("Successfully mounted agent: $agent_name");
    add_detail("Successfully mounted agent: $agent_name");
}

write_log("Automount process completed successfully");
$status->{current_step} = "Completed";
add_detail("Automount process completed successfully"); 