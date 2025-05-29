#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# If script is called with 'remote' argument, just show the message
if [ "$1" = "remote" ]; then
    #echo "No Updates Right now"
    # Check current version from README.md
    if [ -f "/usr/local/openRT/openRTApp/README.md" ]; then
        CURRENT_VER=$(grep "^VER" "/usr/local/openRT/openRTApp/README.md" | awk '{print $2}')
        if [ "$CURRENT_VER" != "1.1" ]; then
            echo "Updating openRTApp from GitHub..."
            rm -rf /usr/local/openRT/openRTApp
            cd /usr/local/openRT
            git clone https://github.com/amcchord/openRT.git temp
            mv temp/openRTApp .
            rm -rf temp
            echo "openRTApp updated to version 1.1"
        else
            echo "openRTApp is already at version 1.1"
        fi
    else
        echo "README.md not found, performing fresh install..."
        cd /usr/local/openRT
        git clone https://github.com/amcchord/openRT.git temp
        mv temp/openRTApp .
        rm -rf temp
        echo "openRTApp installed at version 1.1"
    fi
    exit 0
fi

# Download and execute the remote script
echo "Downloading and executing remote script"
curl -s https://raw.githubusercontent.com/amcchord/openRT/refs/heads/main/setup/githubUpdates.sh | sudo bash -s remote
