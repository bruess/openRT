#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Function to safely stop and remove existing services
cleanup_existing_services() {
    # Stop and disable the old service if it exists
    systemctl stop rtstatus.service 2>/dev/null || true
    systemctl disable rtstatus.service 2>/dev/null || true
    rm -f /etc/systemd/system/rtstatus.service
    
    # Stop and disable the status monitor service if it exists
    systemctl stop openrt-status-monitor.service 2>/dev/null || true
    systemctl disable openrt-status-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/openrt-status-monitor.service
    
    # Reload systemd to recognize changes
    systemctl daemon-reload
    
    echo "Cleaned up existing service installations"
}

# Function to ensure directory exists and has correct permissions
ensure_directory() {
    local dir="$1"
    local owner="$2"
    local group="$3"
    
    mkdir -p "$dir"
    chown "$owner:$group" "$dir"
    chmod 755 "$dir"
}

echo "Starting OpenRT Service setup..."

# Clean up any existing installation
cleanup_existing_services

# Create necessary directories with proper permissions
ensure_directory "/usr/local/openRT/service" "openrt" "openrt"
ensure_directory "/usr/local/openRT/status" "openrt" "openrt"

# Install jq if not already installed
if ! command -v jq &> /dev/null; then
    apt-get update
    apt-get install -y jq
fi

# Create the status monitor script
cat > /usr/local/openRT/service/status_monitor.sh << 'EOF'
#!/bin/bash

# Constants
STATUS_DIR="/usr/local/openRT/status"
SCRIPT_DIR="/usr/local/openRT/openRTApp"
LAST_STATUS_FILE="$STATUS_DIR/last_status"
AUTOMOUNT_FLAG="$STATUS_DIR/automount"
STATUS_JSON="$STATUS_DIR/rtStatus.json"

# Create status directory if it doesn't exist
mkdir -p "$STATUS_DIR"

# Function to cleanup on exit
cleanup() {
    rm -f "$STATUS_JSON.tmp"
    exit 0
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Function to check if automount is enabled
check_automount_enabled() {
    [[ -f "$AUTOMOUNT_FLAG" ]] && [[ "$(cat "$AUTOMOUNT_FLAG")" == "1" ]]
}

# Function to get current pool status
get_pool_status() {
    perl "$SCRIPT_DIR/rtStatus.pl" -j | jq -r '.status'
}

# Function to handle status changes
handle_status_change() {
    local new_status="$1"
    local last_status="$2"
    
    echo "$new_status" > "$LAST_STATUS_FILE"
    
    # If automount is enabled and pool becomes Available
    if check_automount_enabled && [[ "$new_status" == "Available" ]]; then
        # Launch automount in the background
        perl "$SCRIPT_DIR/rtAutoMount.pl" &
    fi
}

# Main loop
while true; do
    # Update status JSON file
    if perl "$SCRIPT_DIR/rtStatus.pl" -j -l > "$STATUS_JSON.tmp"; then
        mv "$STATUS_JSON.tmp" "$STATUS_JSON"
    fi
    
    # Get current status
    current_status=$(get_pool_status)
    
    # Get last status
    last_status=""
    [[ -f "$LAST_STATUS_FILE" ]] && last_status=$(cat "$LAST_STATUS_FILE")
    

    handle_status_change "$current_status" "$last_status"
    
    # Sleep for 5 seconds
    sleep 5
done
EOF

# Create the systemd service file
cat > /etc/systemd/system/openrt-status-monitor.service << 'EOF'
[Unit]
Description=OpenRT Status Monitor
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/openRT/service/status_monitor.sh
WorkingDirectory=/usr/local/openRT
Restart=always
RestartSec=5
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for the monitor script
chmod 755 /usr/local/openRT/service/status_monitor.sh
chown root:root /usr/local/openRT/service/status_monitor.sh

# Reload systemd daemon
systemctl daemon-reload

# Enable and start the status monitor service
systemctl enable openrt-status-monitor
systemctl start openrt-status-monitor

# Verify service is running
if systemctl is-active --quiet openrt-status-monitor.service; then
    echo "OpenRT Status Monitor Service has been successfully installed and started."
    echo "You can check its status with: systemctl status openrt-status-monitor.service"
else
    echo "Error: Service installation completed but service failed to start."
    echo "Please check the logs with: journalctl -u openrt-status-monitor.service"
    exit 1
fi
