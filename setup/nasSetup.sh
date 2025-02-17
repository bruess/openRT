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
mkdir -p /var/run/vsftpd/empty
chmod 755 /rtMount

# Generate random 4-digit number for password
RANDOM_NUM=$(printf "%04d" $((RANDOM % 10000)))
PASSWORD="openRT-$RANDOM_NUM"

# Store password in a secure file
echo "Storing credentials..."
echo "$PASSWORD" > /root/.nas_credentials
chmod 600 /root/.nas_credentials

# Check if explorer user exists, if not create it
if ! id "explorer" &>/dev/null; then
    echo "Creating explorer user..."
    useradd -m -d /rtMount explorer
fi

# Update password
echo "Setting user password..."
echo "explorer:$PASSWORD" | chpasswd
chown explorer:explorer /rtMount

# Install required packages if not already installed
echo "Installing required packages..."
apt-get update
for package in samba nfs-kernel-server vsftpd openssh-server zfsutils-linux; do
    if ! is_installed "$package"; then
        echo "Installing $package..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
    fi
done

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

[rtMount]
path = /rtMount
browseable = yes
read only = no
guest ok = no
valid users = explorer
create mask = 0644
directory mask = 0755
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
echo "/rtMount *(rw,sync,no_subtree_check)" > /etc/exports

# Configure VSFTPD
echo "Configuring VSFTPD..."
if [ -f /etc/vsftpd.conf ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
fi

cat > /etc/vsftpd.conf << EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
force_local_logins_ssl=NO
force_local_data_ssl=NO
ssl_enable=NO
user_sub_token=\$USER
local_root=/rtMount
EOF

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
