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

# Function to create required directories with proper permissions
create_directories() {
    local dirs=("/usr/local/openRT" "/usr/local/openRT/config" "/usr/local/openRT/status" "/usr/local/openRT/logs")
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "Directory $dir already exists, skipping..."
        else
            if [ "$(id -u)" = "0" ]; then
                if ! mkdir -p "$dir" 2>/dev/null; then
                    echo "Error: Failed to create directory $dir"
                    return 1
                fi
            else
                if ! sudo mkdir -p "$dir" 2>/dev/null; then
                    echo "Error: Failed to create directory $dir"
                    return 1
                fi
            fi
            echo "Created directory $dir"
        fi
    done
    
    # Set permissions (only if we have access)
    if [ "$(id -u)" = "0" ]; then
        chmod -R 755 /usr/local/openRT
        chmod -R 700 /usr/local/openRT/status
    else
        sudo chmod -R 755 /usr/local/openRT
        sudo chmod -R 700 /usr/local/openRT/status
    fi
    
    return 0
}

# Function to execute a script with appropriate privileges and track its status
run_script() {
    local script=$1
    local script_name=$(basename "$script")
    local status_file="/usr/local/openRT/status/${script_name}.status"
    
    # Ensure status directory exists and is writable
    if [ ! -w "/usr/local/openRT/status" ]; then
        echo "Error: Status directory is not writable"
        return 1
    fi
    
    # Check if script has already been completed successfully
    if [ -f "$status_file" ] && [ "$(cat "$status_file")" = "completed" ]; then
        echo "Skipping $script_name - already completed successfully"
        return 0
    fi

    echo "Executing $script_name..."
    if [ "$(id -u)" = "0" ]; then
        if bash "$script"; then
            echo "completed" > "$status_file" 2>/dev/null || {
                echo "Warning: Could not write status file $status_file"
                return 1
            }
            return 0
        else
            echo "failed" > "$status_file" 2>/dev/null
            return 1
        fi
    else
        if sudo bash "$script"; then
            sudo sh -c "echo completed > $status_file" 2>/dev/null || {
                echo "Warning: Could not write status file $status_file"
                return 1
            }
            return 0
        else
            sudo sh -c "echo failed > $status_file" 2>/dev/null
            return 1
        fi
    fi
}

# Main execution
echo "OpenRT Installation Setup"
echo "========================"


# Create openrt user if it doesn't exist
if ! id "openrt" &>/dev/null; then
    echo "Creating openrt user..."
    useradd -m -s /bin/bash openrt
    
    # Add openrt to sudo group
    usermod -aG sudo openrt
    
    # Configure sudo without password for openrt
    echo "openrt ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openrt
    chmod 440 /etc/sudoers.d/openrt
fi


# Parse command line arguments
SKIP_CONFIRM=false
while getopts "y" opt; do
    case $opt in
        y)
            SKIP_CONFIRM=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Check for root privileges
if ! check_root; then
    echo "Error: Root privileges are required to install OpenRT."
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Create OpenRT configuration directory
echo "Creating OpenRT configuration directory..."
if ! create_directories; then
    echo "Error: Failed to create and configure OpenRT directories."
    exit 1
fi

# Ask for confirmation unless -y flag is used
if [ "$SKIP_CONFIRM" = false ]; then
    echo
    echo "This script will install OpenRT and its components."
    echo "Configuration will be stored in /usr/local/openRT/"
    echo "The following scripts will be executed (if not already completed):"
    echo "- kioskSetup.sh"
    echo "- nasSetup.sh"
    echo "- uiSetup.sh"
    echo "- serviceSetup.sh"
    echo
    read -p "Are you sure you want to proceed with the installation? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Execute each setup script
echo
echo "Starting OpenRT installation..."
echo

# Array to track failed scripts
declare -a failed_scripts=()

for script in "$SCRIPT_DIR"/{"kioskSetup.sh","nasSetup.sh","uiSetup.sh","serviceSetup.sh"}; do
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
    if ! date > "/usr/local/openRT/status/installation_completed" 2>/dev/null; then
        echo "Warning: Could not write installation completion timestamp"
    fi
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
