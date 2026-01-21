#!/bin/bash
set -e

# User Data Script for SLURM Worker Nodes (Compute Nodes)
# This script runs on first boot to configure SLURM compute nodes

echo "========================================="
echo "Configuring SLURM Worker Node (Compute)"
echo "========================================="

# Variables from Terraform
EFS_ID="${efs_id}"
S3_BUCKET="${s3_bucket}"
HEAD_NODE_IP="${head_node_ip}"
WORKER_INDEX="${worker_index}"

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    nfs-common \
    awscli \
    jq \
    htop \
    tmux \
    git \
    build-essential

# Mount EFS
echo "Mounting EFS: $EFS_ID"
mkdir -p /efs/models
echo "$EFS_ID:/ /efs/models nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
mount -a
chmod 755 /efs/models

# Install SLURM
echo "Installing SLURM..."
apt-get install -y slurm-wlm munge

# Wait for head node to generate munge key (retry for up to 5 minutes)
echo "Waiting for head node munge key..."
for i in {1..30}; do
  if [ -f /etc/munge/munge.key ]; then
    break
  fi
  echo "Attempt $i: Munge key not yet available, waiting..."
  sleep 10
done

# Copy munge key from head node (via shared EFS or manual sync)
# For now, we'll create a temporary key and sync later via SSH
dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key

# Start munge
systemctl enable munge
systemctl restart munge

# Get instance information
PRIVATE_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname -s)

# Create SLURM configuration (minimal - will sync from head node)
mkdir -p /etc/slurm /var/log/slurm /var/spool/slurm/d
chown slurm:slurm /var/log/slurm /var/spool/slurm/d

# Configure GPU resources
echo "NodeName=$HOSTNAME Name=gpu File=/dev/nvidia0" > /etc/slurm/gres.conf
chmod 644 /etc/slurm/gres.conf

# Install Python ML packages
echo "Installing Python ML packages..."
pip3 install --upgrade pip
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip3 install transformers accelerate vllm

# Install shared-model-utils
cd /opt
git clone https://github.com/anthropics/shared-model-utils.git || \
  echo "ModelLoader will be manually installed"
if [ -d "shared-model-utils" ]; then
  cd shared-model-utils
  pip3 install -e .
fi

# Create script to sync SLURM config from head node
cat > /usr/local/bin/sync-slurm-config.sh <<'EOSYNC'
#!/bin/bash
# Sync SLURM configuration from head node

HEAD_NODE="${head_node_ip}"

echo "Syncing SLURM config from head node: $HEAD_NODE"

# Wait for head node to be ready
for i in {1..60}; do
  if ping -c 1 $HEAD_NODE &> /dev/null; then
    echo "Head node is reachable"
    break
  fi
  echo "Waiting for head node... ($i/60)"
  sleep 5
done

# Copy SLURM config files
# This requires SSH key authentication or shared storage
# For now, we'll use a placeholder

echo "Manual sync required. Run on head node:"
echo "  sudo scp /etc/slurm/slurm.conf worker-node:/etc/slurm/"
echo "  sudo scp /etc/munge/munge.key worker-node:/etc/munge/"
echo "Then restart slurmd on worker: sudo systemctl restart slurmd"
EOSYNC

chmod +x /usr/local/bin/sync-slurm-config.sh

# Create welcome message
cat > /etc/motd <<EOF
╔════════════════════════════════════════════════════════════════════════════╗
║                   Los Alamos SLURM GPU Testing Cluster                     ║
║                         WORKER NODE #$((WORKER_INDEX + 1))                              ║
╚════════════════════════════════════════════════════════════════════════════╝

🔧 Worker Node Information:
  Private IP:     $PRIVATE_IP
  Head Node IP:   $HEAD_NODE_IP

📁 Storage:
  /efs/models/    - Shared model storage (EFS)
  S3 Bucket:      - $S3_BUCKET

⚠️  Configuration Required:
  1. Munge key must be synced from head node
  2. SLURM config must be synced from head node
  3. Run: /usr/local/bin/sync-slurm-config.sh

📚 After Configuration:
  - Node will automatically register with SLURM controller
  - Jobs can be submitted from head node
  - GPUs will be available for compute jobs

EOF

# Start slurmd (will fail until config is synced, but will auto-restart)
systemctl enable slurmd
systemctl start slurmd || echo "slurmd will start after config sync"

echo "========================================="
echo "Worker node base configuration complete!"
echo "========================================="
echo "Worker Index: $WORKER_INDEX"
echo "Private IP: $PRIVATE_IP"
echo "Head Node: $HEAD_NODE_IP"
echo "EFS Mount: /efs/models"
echo "========================================="
echo "⚠️  Manual steps required:"
echo "1. SSH into head node"
echo "2. Copy munge key to workers"
echo "3. Update slurm.conf with worker nodes"
echo "4. Restart slurmctld on head node"
echo "5. Restart slurmd on worker nodes"
echo "========================================="
