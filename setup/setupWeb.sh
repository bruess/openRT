#!/bin/bash

# Make sure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Set up variables
WEB_ROOT="/usr/local/openRT/web"
FILES_DIR="$WEB_ROOT/files"
APACHE_CONF="/etc/apache2/conf-available/openrt-files.conf"

# Create files directory if it doesn't exist
mkdir -p "$FILES_DIR"

# Create symlink to rtMount
ln -sf /rtMount "$FILES_DIR/rtMount"

# Create header file
cat > "$FILES_DIR/header.html" << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenRT File Browser</title>
    <link href="../assets/bootstrap/bootstrap.min.css" rel="stylesheet">
    <link href="../assets/fonts/fonts.css" rel="stylesheet">
    <style>
        body {
            font-family: 'D-DIN', sans-serif;
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
        }
        tr:nth-child(odd) td {
            background-color: #343a40;
        }
        tr:nth-child(even) td {
            background-color: #2c3238;
        }
        a {
            color: #fff;
            text-decoration: none;
        }
        a:hover {
            color: #0d6efd;
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
        }
        img {
            filter: invert(1);
        }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container-fluid">
            <div class="d-flex align-items-center">
                <a href="../explore.php" class="back-button">
                    Back to Explorer
                </a>
                <span class="navbar-brand" style="color: white;">OpenRT File Browser</span>
            </div>
            <img src="../assets/images/openRT.png" alt="OpenRT Logo" class="logo">
        </div>
    </nav>
    <div class="container">
EOL

# Create footer file
cat > "$FILES_DIR/footer.html" << 'EOL'
    </div>
    <script src="../assets/bootstrap/bootstrap.bundle.min.js"></script>
</body>
</html>
EOL

# Create Apache configuration
cat > "$APACHE_CONF" << 'EOL'
<Directory "/usr/local/openRT/web/files">
    Options +Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
    
    IndexOptions FancyIndexing VersionSort NameWidth=* HTMLTable Charset=UTF-8
    IndexIgnore .htaccess header.html footer.html
    DirectoryIndex disabled
    
    HeaderName /files/header.html
    ReadmeName /files/footer.html
    
    IndexStyleSheet "/assets/bootstrap/bootstrap.min.css"
    
    # Customize the icons
    DefaultIcon /assets/images/file.png
    AddIcon /assets/images/back.png ..
    AddIcon /assets/images/folder.png ^^DIRECTORY^^
    AddIcon /assets/images/file.png ^^BLANKICON^^
</Directory>
EOL

# Enable the configuration
a2enconf openrt-files

# Set proper permissions
chown -R www-data:www-data "$FILES_DIR"
chmod 755 "$FILES_DIR"

# Restart Apache to apply changes
systemctl restart apache2

echo "Web directory setup complete" 