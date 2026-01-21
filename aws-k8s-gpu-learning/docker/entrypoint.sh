#!/bin/bash
set -e

echo "Starting GPU Development Environment..."

# Generate SSH host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi

# Setup authorized_keys if provided
if [ -f /ssh-keys/authorized_keys ]; then
    echo "Setting up SSH authorized keys..."
    cp /ssh-keys/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Display welcome message
/usr/local/bin/welcome.sh

# Start SSH service
echo "Starting SSH service..."
/usr/sbin/sshd -D -e
