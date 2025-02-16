#!/bin/bash

# Exit on any error
set -e

# Function to check if a package is installed
is_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Generate random 4-digit number for password
RANDOM_NUM=$(printf "%04d" $((RANDOM % 10000)))
PASSWORD="openRT-$RANDOM_NUM"

# Store password in a secure file
echo "$PASSWORD" > /root/.nas_credentials
chmod 600 /root/.nas_credentials

# Create rtMount directory if it doesn't exist
mkdir -p /rtMount
chmod 755 /rtMount

# Check if explorer user exists, if not create it
if ! id "explorer" &>/dev/null; then
    useradd -m -d /rtMount explorer
fi

# Update password
echo "explorer:$PASSWORD" | chpasswd
chown explorer:explorer /rtMount

# Install required packages if not already installed
apt-get update
for package in samba nfs-kernel-server vsftpd openssh-server zfsutils-linux; do
    if ! is_installed "$package"; then
        apt-get install -y "$package"
    fi
done

# Backup original Samba config if it hasn't been backed up
if [ ! -f /etc/samba/smb.conf.original ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.original
fi

# Configure Samba
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

# Restart Samba and set password for Samba user
systemctl restart smbd
systemctl restart nmbd
(echo "$PASSWORD"; echo "$PASSWORD") | smbpasswd -s -a explorer

# Backup original exports if it hasn't been backed up
if [ ! -f /etc/exports.original ]; then
    cp /etc/exports /etc/exports.original
fi

# Remove any existing rtMount entry from exports
sed -i '/\/rtMount/d' /etc/exports

# Configure NFS
echo "/rtMount *(rw,sync,no_subtree_check)" >> /etc/exports
exportfs -ra  # -ra forces re-read of exports and sync
systemctl restart nfs-kernel-server

# Backup original VSFTPD config if it hasn't been backed up
if [ ! -f /etc/vsftpd.conf.original ]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.original
fi

# Configure VSFTPD (FTP)
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

systemctl restart vsftpd

# Configure SFTP (already set up with SSH)
# The user can already access their home directory (/rtMount) via SFTP

# Print the generated password
echo "Setup completed successfully!"
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
