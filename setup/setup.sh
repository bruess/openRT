#!/bin/bash

# Function to check if script has root privileges or can use sudo
check_root() {
    if [ "$(id -u)" = "0" ]; then
        return 0
    elif command -v sudo >/dev/null 2>&1; then
        # Test sudo access without password
        if sudo -n true 2>/dev/null; then
            return 0
        else
            echo "This script requires sudo privileges."
            if sudo true; then
                return 0
            else
                return 1
            fi
        fi
    else
        echo "This script requires root privileges or sudo access."
        return 1
    fi
}

# Function to execute a script with appropriate privileges and track its status
run_script() {
    local script=$1
    local script_name=$(basename "$script")
    local status_file="/usr/local/openRT/status/${script_name}.status"
    
    # Check if script has already been completed successfully
    if [ -f "$status_file" ] && [ "$(cat "$status_file")" = "completed" ]; then
        echo "Skipping $script_name - already completed successfully"
        return 0
    fi

    echo "Executing $script_name..."
    if [ "$(id -u)" = "0" ]; then
        if bash "$script"; then
            echo "completed" > "$status_file"
            return 0
        else
            echo "failed" > "$status_file"
            return 1
        fi
    else
        if sudo bash "$script"; then
            echo "completed" > "$status_file"
            return 0
        else
            echo "failed" > "$status_file"
            return 1
        fi
    fi
}

# Main execution
echo "OpenRT Installation Setup"
echo "========================"

# Check for root privileges
if ! check_root; then
    echo "Error: Root privileges are required to install OpenRT."
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Create OpenRT configuration directory
echo "Creating OpenRT configuration directory..."
mkdir -p /usr/local/openRT/{config,status,logs}
chmod -R 755 /usr/local/openRT
chmod -R 700 /usr/local/openRT/status  # More restrictive permissions for status directory

# Ask for confirmation
echo
echo "This script will install OpenRT and its components."
echo "Configuration will be stored in /usr/local/openRT/"
echo "The following scripts will be executed (if not already completed):"
echo "- kioskSetup.sh"
echo "- nasSetup.sh"
echo "- uiSetup.sh"
echo
read -p "Are you sure you want to proceed with the installation? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Execute each setup script
echo
echo "Starting OpenRT installation..."
echo

# Array to track failed scripts
declare -a failed_scripts=()

for script in "$SCRIPT_DIR"/{"kioskSetup.sh","nasSetup.sh","uiSetup.sh"}; do
    if [ -f "$script" ]; then
        if ! run_script "$script"; then
            failed_scripts+=("$(basename "$script")")
        fi
    else
        echo "Warning: $script not found"
    fi
done

# Print installation summary
echo
echo "Installation Summary:"
echo "===================="

if [ ${#failed_scripts[@]} -eq 0 ]; then
    echo "All scripts completed successfully!"
    echo "OpenRT installation completed!"
    
    # Store successful installation timestamp
    date > "/usr/local/openRT/status/installation_completed"
else
    echo "The following scripts failed:"
    for script in "${failed_scripts[@]}"; do
        echo "- $script"
    done
    echo
    echo "Please fix any errors and run the setup script again."
    echo "Only failed scripts will be re-executed on the next run."
    exit 1
fi

# Print configuration location
echo
echo "Configuration stored in: /usr/local/openRT/"
echo "You can check individual script status in: /usr/local/openRT/status/"
