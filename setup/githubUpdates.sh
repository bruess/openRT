#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# If script is called with 'remote' argument, just show the message
if [ "$1" = "remote" ]; then
    echo "No Updates Right now"
    exit 0
fi

# Download and execute the remote script
echo "Downloading and executing remote script"
curl -s https://raw.githubusercontent.com/amcchord/openRT/refs/heads/main/setup/githubUpdates.sh | sudo bash -s remote
