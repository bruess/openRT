#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Function to safely stop and remove existing service
cleanup_existing_service() {
    # Stop the service if it's running
    systemctl stop rtstatus.service 2>/dev/null || true
    
    # Disable the service if it's enabled
    systemctl disable rtstatus.service 2>/dev/null || true
    
    # Remove the service file if it exists
    rm -f /etc/systemd/system/rtstatus.service
    
    # Reload systemd to recognize changes
    systemctl daemon-reload
    
    echo "Cleaned up existing service installation"
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

echo "Starting RT Status Monitor Service setup..."

# Clean up any existing installation
cleanup_existing_service

# Create necessary directories with proper permissions
ensure_directory "/usr/local/openRT/service" "openrt" "openrt"
ensure_directory "/usr/local/openRT/status" "openrt" "openrt"

# Create the status monitor script
cat > /usr/local/openRT/service/status_monitor.sh << 'EOF'
#!/bin/bash

# Set the working directory
cd /usr/local/openRT

# Ensure the status directory exists
mkdir -p status

# Function to cleanup on exit
cleanup() {
    rm -f "status/rtStatus.json.tmp"
    exit 0
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

while true; do
    # Run rtStatus.pl with JSON output and save to temporary file first
    # This ensures we don't have partial writes
    if ./openRTApp/rtStatus.pl -j -l > "status/rtStatus.json.tmp"; then
        # Only move the file if the command was successful
        mv "status/rtStatus.json.tmp" "status/rtStatus.json"
    fi
    
    # Wait 5 seconds before next run
    sleep 5
done
EOF

# Create the systemd service file
cat > /usr/local/openRT/service/rtstatus.service << 'EOF'
[Unit]
Description=RT Status Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/openRT/service/status_monitor.sh
WorkingDirectory=/usr/local/openRT
User=openrt
Group=openrt
Restart=always
RestartSec=5
# Ensure clean shutdown
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for the monitor script
chmod 755 /usr/local/openRT/service/status_monitor.sh
chown openrt:openrt /usr/local/openRT/service/status_monitor.sh

# Install the service
cp /usr/local/openRT/service/rtstatus.service /etc/systemd/system/

# Reload systemd to recognize new service
systemctl daemon-reload

# Enable and start the service
systemctl enable rtstatus.service
systemctl start rtstatus.service

# Verify service is running
if systemctl is-active --quiet rtstatus.service; then
    echo "RT Status Monitor Service has been successfully installed and started."
    echo "You can check its status with: systemctl status rtstatus.service"
    echo "Status output will be available at: /usr/local/openRT/status/rtStatus.json"
else
    echo "Error: Service installation completed but service failed to start."
    echo "Please check the logs with: journalctl -u rtstatus.service"
    exit 1
fi
