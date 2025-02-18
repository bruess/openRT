#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to clean up existing theme
cleanup_existing_theme() {
    # Remove existing theme files if they exist
    rm -rf /usr/share/plymouth/themes/openrt
    # Remove existing background setup if it exists
    rm -f /etc/profile.d/set-background.sh
    # Remove existing background if it exists
    rm -f /usr/local/share/backgrounds/openrt-logo.png
}

# Ensure Plymouth and all required packages are installed
echo "Checking Plymouth installation..."
PLYMOUTH_PACKAGES="plymouth plymouth-themes plymouth-label plymouth-x11"
for package in $PLYMOUTH_PACKAGES; do
    if ! dpkg -l | grep -q "^ii.*$package"; then
        echo "Installing $package..."
        apt-get update
        apt-get install -y $package
    fi
done

# Clean up any existing installation
cleanup_existing_theme

# Create directories for Plymouth theme
mkdir -p /usr/share/plymouth/themes/openrt
cd /usr/share/plymouth/themes/openrt

# Download the OpenRT logo
echo "Downloading OpenRT logo..."
wget -q https://raw.githubusercontent.com/amcchord/openRT/main/static/openRT.png -O openrt-logo.png
if [ ! -f openrt-logo.png ]; then
    echo "Failed to download logo from GitHub"
    # Fallback to local copy if available
    if [ -f /usr/local/openRT/static/openRT.png ]; then
        echo "Using local copy of OpenRT logo..."
        cp /usr/local/openRT/static/openRT.png openrt-logo.png
    else
        echo "Error: Could not find OpenRT logo. Please ensure the logo exists at /usr/local/openRT/static/openRT.png"
        exit 1
    fi
fi

# Verify the logo file
if [ ! -s openrt-logo.png ]; then
    echo "Error: The logo file is empty"
    exit 1
fi

echo "Logo file verified successfully"

# Ensure correct permissions
chmod 644 openrt-logo.png

# Create Plymouth theme configuration
cat > openrt.plymouth << EOL
[Plymouth Theme]
Name=OpenRT
Description=Display the OpenRT image at boot
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/openrt
ScriptFile=/usr/share/plymouth/themes/openrt/openrt.script
EOL

# Create Plymouth script
cat > openrt.script << EOL
image = Image("openrt-logo.png");

pos_x = Window.GetWidth()/2 - image.GetWidth()/2;
pos_y = Window.GetHeight()/2 - image.GetHeight()/2;

sprite = Sprite(image);
sprite.SetX(pos_x);
sprite.SetY(pos_y);

fun refresh_callback () {
  sprite.SetOpacity(1);
  sprite.SetZ(15);
}

Plymouth.SetRefreshFunction(refresh_callback);
EOL

# Install and set the theme
echo "Setting up Plymouth theme..."
# Remove stale plymouth alternative if present (fix for repeated runs)
update-alternatives --remove default.plymouth /usr/share/plymouth/themes/openrt/openrt.plymouth 2>/dev/null || true
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/openrt/openrt.plymouth 100
update-alternatives --set default.plymouth /usr/share/plymouth/themes/openrt/openrt.plymouth

# Update initramfs to include the new theme
echo "Updating initramfs..."
update-initramfs -u -k all

# Update GRUB configuration
# First, backup the original if no backup exists
if [ ! -f /etc/default/grub.bak ]; then
    cp /etc/default/grub /etc/default/grub.bak
fi

# Update GRUB configuration if needed
echo "Updating GRUB configuration..."
if ! grep -q "quiet splash" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
fi

# Ensure Plymouth is enabled in GRUB
if ! grep -q "^GRUB_CMDLINE_LINUX_DEFAULT.*splash" /etc/default/grub; then
    # Add splash if it's not there
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' /etc/default/grub
fi

update-grub

echo "Setting default Plymouth theme to openrt..."
plymouth-set-default-theme openrt -R

# Set up background for Chromium loading
echo "Setting up background..."
# Create a directory for the background if it doesn't exist
mkdir -p /usr/local/share/backgrounds

# Copy the logo to backgrounds directory
cp openrt-logo.png /usr/local/share/backgrounds/

# Set up feh to set background
if ! command -v feh &> /dev/null; then
    echo "Installing feh..."
    apt-get update
    apt-get install -y feh
fi

# Remove old background setting script if it exists
rm -f /etc/profile.d/set-background.sh

# Add background setting to .xinitrc
# First check if .xinitrc exists in /etc/skel (for new users)
if [ ! -f /etc/skel/.xinitrc ]; then
    touch /etc/skel/.xinitrc
    chmod 644 /etc/skel/.xinitrc
fi

# Remove any existing feh background commands
sed -i '/feh --bg-scale/d' /etc/skel/.xinitrc

# Add the background setting command
echo 'feh --bg-scale /usr/local/share/backgrounds/openrt-logo.png &' >> /etc/skel/.xinitrc

# Also set it for existing users
for userdir in /home/*; do
    if [ -d "$userdir" ]; then
        username=$(basename "$userdir")
        # Skip if it's not a real user directory
        if id "$username" >/dev/null 2>&1; then
            echo "Setting up .xinitrc for user $username"
            if [ ! -f "$userdir/.xinitrc" ]; then
                cp /etc/skel/.xinitrc "$userdir/.xinitrc"
            else
                # Remove any existing feh background commands
                sed -i '/feh --bg-scale/d' "$userdir/.xinitrc"
                # Add the new command
                echo 'feh --bg-scale /usr/local/share/backgrounds/openrt-logo.png &' >> "$userdir/.xinitrc"
            fi
            chown $username:$username "$userdir/.xinitrc"
        fi
    fi
done

echo "Setup completed successfully! Please reboot to see the changes."
