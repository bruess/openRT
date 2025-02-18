#!/bin/bash

# Make sure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check and install required packages
echo "Checking required packages..."
REQUIRED_PACKAGES="wget unzip"
MISSING_PACKAGES=""

for package in $REQUIRED_PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        MISSING_PACKAGES="$MISSING_PACKAGES $package"
    fi
done

if [ ! -z "$MISSING_PACKAGES" ]; then
    echo "Installing missing packages:$MISSING_PACKAGES"
    apt-get update -qq
    apt-get install -y $MISSING_PACKAGES
fi

# Set up variables
WEB_ROOT="/usr/local/openRT/web"
FILES_DIR="$WEB_ROOT/files"
TEMPLATES_DIR="$WEB_ROOT/templates"
APACHE_CONF="/etc/apache2/conf-available/openrt-files.conf"
FONTAWESOME_VERSION="6.5.1"

echo "Setting up OpenRT web directory..."

# Create all necessary directories
echo "Creating required directories..."
for dir in \
    "$WEB_ROOT/assets" \
    "$WEB_ROOT/assets/bootstrap" \
    "$WEB_ROOT/assets/fonts" \
    "$WEB_ROOT/assets/images" \
    "$WEB_ROOT/assets/fontawesome" \
    "$WEB_ROOT/assets/fontawesome/css" \
    "$WEB_ROOT/assets/fontawesome/webfonts" \
    "$TEMPLATES_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "$dir"
        chown www-data:www-data "$dir"
        chmod 755 "$dir"
    fi
done

# Create files directory as a symlink to /rtMount
echo "Setting up files directory..."
if [ -L "$FILES_DIR" ]; then
    echo "Updating files symlink..."
    rm -f "$FILES_DIR"
elif [ -e "$FILES_DIR" ]; then
    echo "Removing existing files directory..."
    rm -rf "$FILES_DIR"
fi
ln -sf /rtMount "$FILES_DIR"

# Download and extract Font Awesome
echo "Setting up Font Awesome..."
if [ ! -f "$WEB_ROOT/assets/fontawesome/css/all.min.css" ]; then
    echo "Downloading Font Awesome ${FONTAWESOME_VERSION}..."
    TEMP_DIR=$(mktemp -d)
    
    # Download with progress indicator
    wget --progress=dot:giga "https://use.fontawesome.com/releases/v${FONTAWESOME_VERSION}/fontawesome-free-${FONTAWESOME_VERSION}-web.zip" -O "${TEMP_DIR}/fontawesome.zip"
    
    if [ $? -ne 0 ]; then
        echo "Failed to download Font Awesome"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
    
    echo "Extracting Font Awesome..."
    unzip -q "${TEMP_DIR}/fontawesome.zip" -d "${TEMP_DIR}"
    
    echo "Installing Font Awesome files..."
    cp -f "${TEMP_DIR}/fontawesome-free-${FONTAWESOME_VERSION}-web/css/all.min.css" "$WEB_ROOT/assets/fontawesome/css/"
    cp -f "${TEMP_DIR}/fontawesome-free-${FONTAWESOME_VERSION}-web/webfonts/"* "$WEB_ROOT/assets/fontawesome/webfonts/"
    
    # Set proper ownership and permissions
    chown -R www-data:www-data "$WEB_ROOT/assets/fontawesome"
    find "$WEB_ROOT/assets/fontawesome" -type d -exec chmod 755 {} \;
    find "$WEB_ROOT/assets/fontawesome" -type f -exec chmod 644 {} \;
    
    rm -rf "${TEMP_DIR}"
    echo "Font Awesome installed successfully"
else
    echo "Font Awesome already installed"
fi

# Verify Font Awesome installation
if [ ! -f "$WEB_ROOT/assets/fontawesome/css/all.min.css" ]; then
    echo "Error: Font Awesome CSS file not found after installation"
    exit 1
fi

if [ ! "$(ls -A "$WEB_ROOT/assets/fontawesome/webfonts/")" ]; then
    echo "Error: Font Awesome webfonts directory is empty"
    exit 1
fi

# Download and setup Bootstrap
BOOTSTRAP_VERSION="5.3.2"
echo "Setting up Bootstrap..."

# Check if any Bootstrap files are missing
BOOTSTRAP_FILES_MISSING=0
if [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.min.css" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.min.css.map" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js.map" ]; then
    BOOTSTRAP_FILES_MISSING=1
fi

if [ $BOOTSTRAP_FILES_MISSING -eq 1 ]; then
    echo "Downloading Bootstrap ${BOOTSTRAP_VERSION}..."
    
    # Download Bootstrap CSS and its source map
    wget --progress=dot:giga "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/css/bootstrap.min.css" -O "$WEB_ROOT/assets/bootstrap/bootstrap.min.css"
    wget --progress=dot:giga "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/css/bootstrap.min.css.map" -O "$WEB_ROOT/assets/bootstrap/bootstrap.min.css.map"
    
    # Download Bootstrap JS and its source map
    wget --progress=dot:giga "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/js/bootstrap.bundle.min.js" -O "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js"
    wget --progress=dot:giga "https://cdn.jsdelivr.net/npm/bootstrap@${BOOTSTRAP_VERSION}/dist/js/bootstrap.bundle.min.js.map" -O "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js.map"
    
    # Set proper ownership and permissions
    chown -R www-data:www-data "$WEB_ROOT/assets/bootstrap"
    find "$WEB_ROOT/assets/bootstrap" -type d -exec chmod 755 {} \;
    find "$WEB_ROOT/assets/bootstrap" -type f -exec chmod 644 {} \;
    
    echo "Bootstrap installed successfully"
else
    echo "Bootstrap files already present"
fi

# Verify Bootstrap installation
if [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.min.css" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.min.css.map" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js" ] || \
   [ ! -f "$WEB_ROOT/assets/bootstrap/bootstrap.bundle.min.js.map" ]; then
    echo "Error: Some Bootstrap files are missing after installation"
    exit 1
fi

# Function to create or update a file
create_or_update_file() {
    local file="$1"
    local content="$2"
    local description="$3"
    
    echo "Setting up $description..."
    echo "$content" > "$file"
}

# Create header file
header_content='<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenRT File Browser</title>
    <link href="/assets/bootstrap/bootstrap.min.css" rel="stylesheet">
    <link href="/assets/fonts/fonts.css" rel="stylesheet">
    <link href="/assets/fontawesome/css/all.min.css" rel="stylesheet">
    <style>
        body {
            font-family: '\''D-DIN'\'', sans-serif;
            background-color: #212529;
            color: #fff;
            padding-bottom: 2rem;
        }
        .navbar {
            background-color: #1a1d20;
            color: white;
            border-bottom: 1px solid #2c3238;
            margin-bottom: 2rem;
        }
        .logo {
            max-height: 50px;
            margin: 10px;
        }
        .back-button {
            background-color: #0d6efd;
            color: white;
            text-decoration: none;
            padding: 0.5rem 1rem;
            border-radius: 0.375rem;
            transition: background-color 0.2s;
            margin-right: 1rem;
        }
        .back-button:hover {
            background-color: #0b5ed7;
            color: white;
        }
        table {
            background-color: #2c3238;
            border-radius: 0.375rem;
            border: 1px solid #373d44;
            width: 100%;
            margin-bottom: 1rem;
        }
        th {
            background-color: #1a1d20 !important;
            color: #fff !important;
            border-bottom: 1px solid #373d44;
            padding: 0.75rem;
            font-weight: 600;
        }
        td {
            padding: 0.75rem;
            border-bottom: 1px solid #373d44;
            color: #fff;
        }
        tr:nth-child(odd) td {
            background-color: #343a40;
        }
        tr:nth-child(even) td {
            background-color: #2c3238;
        }
        tr:hover td {
            background-color: #3d444b;
        }
        a {
            color: #fff;
            text-decoration: none;
        }
        a:hover {
            color: #0d6efd;
            text-decoration: none;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 1rem;
        }
        h1 {
            font-size: 1.5rem;
            margin-bottom: 1rem;
            color: #fff;
        }
        hr {
            border-color: #373d44;
            opacity: 0.25;
        }
        /* Icon styles */
        td img {
            display: none;
        }
        td a::before {
            font-family: "Font Awesome 6 Free";
            font-weight: 900;
            margin-right: 0.5rem;
            color: #adb5bd;
        }
        td a[href$="/"]::before {
            content: "\f07b";  /* folder icon */
            color: #ffd700;
        }
        td a[href="../"]::before {
            content: "\f060";  /* back arrow */
            color: #0d6efd;
        }
        td a:not([href$="/"])::before {
            content: "\f15b";  /* file icon */
            color: #adb5bd;
        }
        /* Table header styles */
        th a {
            color: #fff !important;
            text-decoration: none;
        }
        th a:hover {
            color: #0d6efd !important;
            text-decoration: none;
        }
        /* Size and Date columns */
        td:nth-child(2), td:nth-child(3) {
            color: #adb5bd;
        }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container-fluid">
            <div class="d-flex align-items-center">
                <a href="/explore.php" class="back-button">
                    <i class="fas fa-arrow-left"></i> Back to Explorer
                </a>
                <span class="navbar-brand" style="color: white;">OpenRT File Browser</span>
            </div>
            <img src="/assets/images/openRT.png" alt="OpenRT Logo" class="logo">
        </div>
    </nav>
    <div class="container">'

footer_content='    </div>
    <script src="/assets/bootstrap/bootstrap.bundle.min.js"></script>
</body>
</html>'

# Create or update header and footer files
create_or_update_file "$TEMPLATES_DIR/header.html" "$header_content" "header template"
create_or_update_file "$TEMPLATES_DIR/footer.html" "$footer_content" "footer template"

# Create Apache configuration
apache_conf_content='<Directory "/usr/local/openRT/web/files">
    Options +Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
    
    IndexOptions FancyIndexing VersionSort NameWidth=* HTMLTable Charset=UTF-8
    IndexIgnore .htaccess header.html footer.html
    DirectoryIndex disabled
    
    HeaderName /templates/header.html
    ReadmeName /templates/footer.html
    
    IndexStyleSheet "/assets/bootstrap/bootstrap.min.css"
</Directory>

Alias /assets "/usr/local/openRT/web/assets"
<Directory "/usr/local/openRT/web/assets">
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

Alias /templates "/usr/local/openRT/web/templates"
<Directory "/usr/local/openRT/web/templates">
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>'

# Create or update Apache configuration
echo "Setting up Apache configuration..."
create_or_update_file "$APACHE_CONF" "$apache_conf_content" "Apache configuration"

# Check if configuration is already enabled
if [ ! -f "/etc/apache2/conf-enabled/openrt-files.conf" ]; then
    echo "Enabling Apache configuration..."
    a2enconf openrt-files
fi

# Set proper permissions
echo "Setting permissions..."
chown -R www-data:www-data "$TEMPLATES_DIR" "$WEB_ROOT/assets/fontawesome"
chmod 755 "$TEMPLATES_DIR" "$WEB_ROOT/assets/fontawesome"

# Restart Apache only if configuration has changed
if [ "$(md5sum "$APACHE_CONF" | cut -d' ' -f1)" != "$(md5sum "/etc/apache2/conf-enabled/openrt-files.conf" 2>/dev/null | cut -d' ' -f1)" ]; then
    echo "Restarting Apache..."
    systemctl restart apache2
else
    echo "Apache configuration unchanged, no restart needed"
fi

echo "Web directory setup complete" 