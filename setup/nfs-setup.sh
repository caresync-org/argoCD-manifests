#!/bin/bash
# =============================================================================
# NFS Server Setup Script
# Run this on EC2 Instance 4 (HAProxy + NFS server)
# =============================================================================

set -e

echo "=== Installing NFS Server ==="
sudo apt-get update -y
sudo apt-get install -y nfs-kernel-server

echo "=== Creating export directory ==="
sudo mkdir -p /exports/caresync
sudo chown -R nobody:nogroup /exports/caresync
sudo chmod 777 /exports/caresync

echo "=== Configuring NFS exports ==="
# Remove any existing entry to avoid duplicates
sudo sed -i '/\/exports\/caresync/d' /etc/exports
echo "/exports/caresync *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports

echo "=== Applying exports ==="
sudo exportfs -ra

echo "=== Enabling and starting NFS server ==="
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

echo ""
echo "=== NFS Server Setup Complete ==="
echo "NFS is exporting: /exports/caresync"
echo ""
echo "Verify with:"
echo "  sudo systemctl status nfs-kernel-server"
echo "  showmount -e localhost"
echo ""
echo "Run the following on EACH worker node:"
echo "  sudo apt-get install -y nfs-common"
echo "  sudo mkdir -p /mnt/nfs"
echo "  sudo mount <THIS-SERVER-IP>:/exports/caresync /mnt/nfs"
echo "  df -h | grep nfs"
