#!/bin/bash

# Exit on any error
set -e

echo "Starting NAS Setup..."

# Function to check if a package is installed
is_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Create necessary directories
echo "Creating required directories..."
mkdir -p /rtMount
chmod 755 /rtMount
chown root:root /rtMount

# Generate random 4-digit number for password
RANDOM_NUM=$(printf "%04d" $((RANDOM % 10000)))
PASSWORD="openRT-$RANDOM_NUM"

# Store password in a secure file
echo "Storing credentials..."
echo "$PASSWORD" > /root/.nas_credentials
chmod 600 /root/.nas_credentials
# Create status directory if it doesn't exist
mkdir -p /usr/local/openRT/status

# Store explorer credentials in status directory
echo "$PASSWORD" > /usr/local/openRT/status/explorer
chmod 600 /usr/local/openRT/status/explorer
chown openrt:openrt /usr/local/openRT/status/explorer

# Check if explorer user exists, if not create it
if ! id "explorer" &>/dev/null; then
    echo "Creating explorer user..."
    useradd -m -s /bin/bash explorer
    # Create home directory for explorer but not in /rtMount
    mkdir -p /home/explorer
    chown explorer:explorer /home/explorer
fi

# Update password
echo "Setting user password..."
echo "explorer:$PASSWORD" | chpasswd

# Install required packages if not already installed
echo "Installing required packages..."
apt-get update

# Force reinstall of nfs-kernel-server to ensure it's properly installed
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server

# Ensure ACL package is installed first
echo "Installing and verifying ACL package..."
DEBIAN_FRONTEND=noninteractive apt-get install -y acl
if ! command -v setfacl &> /dev/null; then
    echo "Error: setfacl command not found after installing acl package. Exiting."
    exit 1
fi

for package in samba smbclient vsftpd openssh-server zfsutils-linux; do
    if ! is_installed "$package"; then
        echo "Installing $package..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
    fi
done

# Verify NFS installation
if ! command -v exportfs >/dev/null 2>&1; then
    echo "Error: NFS utilities not properly installed. Attempting to fix..."
    DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y nfs-kernel-server
    if ! command -v exportfs >/dev/null 2>&1; then
        echo "Failed to install NFS utilities. Please check your system configuration."
        exit 1
    fi
fi

# Backup and configure Samba
echo "Configuring Samba..."
if [ -f /etc/samba/smb.conf ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
fi

cat > /etc/samba/smb.conf << EOF
[global]
workgroup = WORKGROUP
security = user
map to guest = bad user
unix charset = UTF-8
dos charset = CP932
unix extensions = yes
map archive = no
map readonly = yes
create mask = 0444
directory mask = 0555
force create mode = 0444
force directory mode = 0555

[rtMount]
path = /rtMount
browseable = yes
read only = yes
guest ok = no
valid users = explorer
force user = root
force group = root
EOF

# Configure NFS
echo "Configuring NFS..."
# Create exports file if it doesn't exist
touch /etc/exports

# Backup original exports if it exists
if [ -f /etc/exports ] && [ -s /etc/exports ]; then
    cp /etc/exports /etc/exports.backup
fi

# Remove any existing rtMount entry and add new one
sed -i '/\/rtMount/d' /etc/exports
echo "/rtMount *(ro,sync,no_subtree_check,all_squash,anonuid=$(id -u explorer),anongid=$(id -g explorer))" > /etc/exports

# Configure VSFTPD
echo "Configuring VSFTPD..."
if [ -f /etc/vsftpd.conf ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
fi

# Create necessary FTP directories
mkdir -p /var/run/vsftpd
mkdir -p /var/run/vsftpd/empty
chmod 755 /var/run/vsftpd
chmod 755 /var/run/vsftpd/empty

# Ensure log file exists and has correct permissions
touch /var/log/vsftpd.log
chmod 644 /var/log/vsftpd.log
chown root:adm /var/log/vsftpd.log

cat > /etc/vsftpd.conf << EOF
# Run in standalone mode
listen=YES
listen_ipv6=NO

# Access control
anonymous_enable=NO
local_enable=YES
write_enable=NO
download_enable=YES
dirlist_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/rtMount
userlist_enable=NO
tcp_wrappers=NO

# Security
ssl_enable=NO
force_local_logins_ssl=NO
force_local_data_ssl=NO
require_ssl_reuse=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
port_enable=YES

# Logging and features
xferlog_enable=YES
xferlog_std_format=YES
xferlog_file=/var/log/vsftpd.log
dual_log_enable=YES
log_ftp_protocol=YES
syslog_enable=YES

# Performance and timeouts
idle_session_timeout=600
data_connection_timeout=120
accept_timeout=60
connect_timeout=60

# System settings
seccomp_sandbox=NO
pam_service_name=vsftpd
secure_chroot_dir=/var/run/vsftpd/empty
hide_ids=YES

# Directory settings
dirmessage_enable=YES
use_localtime=YES
text_userdb_names=YES
EOF

# Ensure PAM configuration is correct for VSFTPD
cat > /etc/pam.d/vsftpd << EOF
#%PAM-1.0
auth    required pam_unix.so nullok_secure
account required pam_unix.so
session required pam_unix.so
EOF

# Set up Samba user and password
echo "Setting up Samba user..."
(echo "$PASSWORD"; echo "$PASSWORD") | smbpasswd -s -a explorer

# Set default ACLs for /rtMount to ensure new ZFS mounts inherit correct permissions
setfacl -d -m u:explorer:r-x /rtMount
setfacl -d -m g:explorer:r-x /rtMount

# Create a welcome message
echo "Creating welcome message..."
cat > /rtMount/README.txt << EOF
Welcome to the OpenRT File Server

This directory contains ZFS filesystems that are mounted read-only.
You can browse and download files but cannot modify them.

For support, please contact your system administrator.
EOF

chmod 444 /rtMount/README.txt
chown root:root /rtMount/README.txt

# Restart services
echo "Restarting services..."
systemctl restart smbd || echo "Warning: Failed to restart Samba"
systemctl restart nmbd || echo "Warning: Failed to restart NMB"
exportfs -ra || echo "Warning: Failed to refresh exports"
systemctl restart nfs-kernel-server || echo "Warning: Failed to restart NFS"
systemctl restart vsftpd || echo "Warning: Failed to restart VSFTPD"

# Enable services to start on boot
echo "Enabling services..."
systemctl enable smbd
systemctl enable nmbd
systemctl enable nfs-kernel-server
systemctl enable vsftpd
systemctl enable ssh

# Verify Samba user setup
echo "Verifying Samba configuration..."
pdbedit -L | grep -q "explorer" || {
    echo "Warning: Samba user verification failed. Attempting to fix..."
    (echo "$PASSWORD"; echo "$PASSWORD") | smbpasswd -s -a explorer
}

# Print the generated password
echo -e "\nSetup completed successfully!"
echo "Username: explorer"
echo "Password: $PASSWORD"
echo "Password has been stored in /root/.nas_credentials"
echo "Please note this file is only accessible by root for security."

# Print status of services
echo -e "\nService Status:"
for service in smbd nmbd nfs-kernel-server vsftpd ssh; do
    status=$(systemctl is-active "$service")
    echo "$service: $status"
done

# Final verification of permissions
echo -e "\nVerifying final permissions..."
ls -la /rtMount
getfacl /rtMount

# Print connection information
echo -e "\nConnection Information:"
echo "SMB/CIFS: \\\\$(hostname -I | awk '{print $1}')\rtMount"
echo "FTP: ftp://$(hostname -I | awk '{print $1}'):21/"
echo "NFS: $(hostname -I | awk '{print $1}'):/rtMount"
echo "Username: explorer"
echo "Password: $PASSWORD"

echo -e "\nNOTE: All access is read-only. ZFS filesystems mounted under /rtMount"
echo "will inherit read-only permissions for the explorer user."
