#!/bin/bash

# Kiosk Mode Setup Script
# This script configures the system to boot directly into Chromium browser
# in kiosk mode, displaying a local webpage without requiring login.

set -e  # Exit on any error

# Get the real user (not root) when script is run with sudo
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Function to check if a package is installed
package_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Function to create a file only if it doesn't exist
create_file_if_not_exists() {
    local file="$1"
    local content="$2"
    if [ ! -f "$file" ]; then
        echo "$content" > "$file"
        # If the file is in REAL_HOME, ensure correct ownership
        if [[ "$file" == "$REAL_HOME"* ]]; then
            chown "$REAL_USER:$REAL_USER" "$file"
        fi
    fi
}

echo "Starting kiosk mode setup..."

# Ensure script is run with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Install required packages if not already installed
PACKAGES="chromium-browser apache2 php libapache2-mod-php ratpoison xserver-xorg xinit libjson-perl"
for pkg in $PACKAGES; do
    if ! package_installed "$pkg"; then
        echo "Installing $pkg..."
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    fi
done

# Stop nginx if it's running and remove it
systemctl stop nginx 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get remove -y nginx || true

# Create web directory and set permissions
WEBPAGE_DIR="/usr/local/openRT/web"
STATUS_DIR="/usr/local/openRT/status"
APP_DIR="/usr/local/openRT/openRTApp"

# Create directories if they don't exist
mkdir -p "$WEBPAGE_DIR"
mkdir -p "$STATUS_DIR"
mkdir -p "$APP_DIR"

# Create a group for openRT access if it doesn't exist
groupadd -f openrt

# Add www-data user to openrt group
usermod -a -G openrt www-data

# Set directory ownership and permissions
# Web directory: owned by www-data, readable by openrt group
chown -R www-data:openrt "$WEBPAGE_DIR"
chmod -R 755 "$WEBPAGE_DIR"

# Status directory: group readable by openrt
chown -R root:openrt "$STATUS_DIR"
chmod -R 775 "$STATUS_DIR"

# App directory: executable by openrt group
chown -R root:openrt "$APP_DIR"
chmod -R 775 "$APP_DIR"

# Create a specific sudoers entry for www-data
echo "# Allow www-data to execute specific commands without password
www-data ALL=(ALL) NOPASSWD: /usr/local/openRT/openRTApp/rtStatus.pl
www-data ALL=(ALL) NOPASSWD: /usr/local/openRT/openRTApp/rtMetadata.pl
www-data ALL=(ALL) NOPASSWD: /usr/local/openRT/openRTApp/rtFileMount.pl
www-data ALL=(ALL) NOPASSWD: /usr/local/openRT/openRTApp/rtImport.pl" > /etc/sudoers.d/www-data-openrt

# Set proper permissions for the sudoers file
chmod 440 /etc/sudoers.d/www-data-openrt

# Ensure parent directory is accessible
chown root:openrt "/usr/local/openRT"
chmod 755 "/usr/local/openRT"

# Create a PHP info file for testing PHP installation
create_file_if_not_exists "$WEBPAGE_DIR/phpinfo.php" "<?php phpinfo(); ?>"

# Create main index file
create_file_if_not_exists "$WEBPAGE_DIR/index.php" "<?php
// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);
?>
<!DOCTYPE html>
<html>
<head>
    <title>Kiosk Display</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background-color: #f0f0f0;
        }
        h1 {
            font-size: 48px;
            color: #333;
        }
    </style>
</head>
<body>
    <h1>Hello World</h1>
    <?php
    // Example of PHP functionality
    echo '<p>Server Time: ' . date('Y-m-d H:i:s') . '</p>';
    ?>
</body>
</html>"

# Enable Apache modules
a2enmod php || true
a2enmod rewrite || true

# Configure Apache
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/local/openRT/web
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    <Directory /usr/local/openRT/web>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Restart Apache
systemctl restart apache2

# Configure automatic login
mkdir -p /etc/systemd/system/getty@tty1.service.d/
tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $REAL_USER --noclear %I \$TERM
EOF

# Create .xinitrc for X server startup
create_file_if_not_exists "$REAL_HOME/.xinitrc" "#!/bin/bash
xset s off
xset s noblank
xset -dpms

# Start ratpoison
exec ratpoison &

# Wait a moment for the window manager to start
sleep 2

# Start Chromium in kiosk mode
exec chromium-browser --kiosk --incognito --disable-translate --no-first-run --fast --fast-start --disable-infobars --disable-features=TranslateUI --disable-session-crashed-bubble http://localhost/index.php"

# Make .xinitrc executable
chmod +x "$REAL_HOME/.xinitrc"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.xinitrc"

# Add startx to .bash_profile to auto-start X
create_file_if_not_exists "$REAL_HOME/.bash_profile" "#!/bin/bash
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    startx
fi"

# Make .bash_profile executable
chmod +x "$REAL_HOME/.bash_profile"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.bash_profile"

# Disable any existing display manager
systemctl disable gdm3 2>/dev/null || true
systemctl disable lightdm 2>/dev/null || true

# Create minimal ratpoison config
create_file_if_not_exists "$REAL_HOME/.ratpoisonrc" "startup_message off
set border 0
set padding 0 0 0 0
set bargravity n
set font fixed"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.ratpoisonrc"

echo "Setup completed successfully!"
echo "Please reboot the system for changes to take effect."
echo "You can test PHP functionality by visiting http://localhost/phpinfo.php"
