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
    echo "Failed to download logo"
    exit 1
fi

# Create Plymouth theme configuration
cat > openrt.plymouth << EOL
[Plymouth Theme]
Name=OpenRT
Description=OpenRT Boot Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/openrt
ScriptFile=/usr/share/plymouth/themes/openrt/openrt.script
EOL

# Create Plymouth script
cat > openrt.script << EOL
wallpaper_image = Image("openrt-logo.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

scaled_image = wallpaper_image.Scale(screen_width, screen_height);
scaled_image = scaled_image.SetOpacity(1);

fun refresh_callback ()
{
    scaled_image.SetX(0);
    scaled_image.SetY(0);
    scaled_image.Draw();
}

Plymouth.SetRefreshFunction(refresh_callback);
EOL

# Install and set the theme
echo "Setting up Plymouth theme..."
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

# Create new background setting script
cat > /etc/profile.d/set-background.sh << EOL
#!/bin/bash
# Set background using feh if running in X environment
if [ -n "\$DISPLAY" ]; then
    feh --bg-scale /usr/local/share/backgrounds/openrt-logo.png &
fi
EOL

chmod +x /etc/profile.d/set-background.sh

echo "Setup completed successfully! Please reboot to see the changes."
