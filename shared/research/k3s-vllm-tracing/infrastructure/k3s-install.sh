#!/bin/bash
#
# k3s-install.sh - Install K3s with NVIDIA GPU Support
#
# Installs K3s (lightweight Kubernetes) with NVIDIA Container Toolkit
# and GPU device plugin for running GPU workloads
#
# Requirements:
#   - Ubuntu 22.04
#   - NVIDIA GPU with drivers installed
#   - Root/sudo access
#
# Usage:
#   sudo ./k3s-install.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         K3s Installation with NVIDIA GPU Support             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Check NVIDIA GPU and drivers
print_step "Checking NVIDIA GPU and drivers..."

if ! command -v nvidia-smi &> /dev/null; then
    print_error "nvidia-smi not found. Please install NVIDIA drivers first."
    echo "  Run: sudo ubuntu-drivers install --gpgpu"
    exit 1
fi

nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
echo ""

# Step 2: Install NVIDIA Container Toolkit
print_step "Installing NVIDIA Container Toolkit..."

# Add repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit

print_step "✓ NVIDIA Container Toolkit installed"

# Step 3: Install K3s
print_step "Installing K3s..."

curl -sfL https://get.k3s.io | sh -s - \
    --container-runtime-endpoint unix:///run/k3s/containerd/containerd.sock \
    --write-kubeconfig-mode 644

# Wait for K3s to be ready
print_step "Waiting for K3s to be ready..."
sleep 10

# Check K3s status
systemctl status k3s --no-pager | head -10

print_step "✓ K3s installed"

# Step 4: Configure containerd for NVIDIA runtime
print_step "Configuring containerd for NVIDIA runtime..."

# Generate NVIDIA CDI specification
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Configure containerd
nvidia-ctk runtime configure \
    --runtime=containerd \
    --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml

# Restart K3s to apply changes
systemctl restart k3s

print_step "✓ Containerd configured for NVIDIA runtime"

# Step 5: Wait for K3s to restart
print_step "Waiting for K3s to restart..."
sleep 15

# Step 6: Set up kubectl access for non-root user
print_step "Setting up kubectl access..."

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$USER_HOME/.kube"
    cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.kube"
    chmod 600 "$USER_HOME/.kube/config"

    print_step "✓ kubectl configured for user: $SUDO_USER"
    echo "  Run as $SUDO_USER: export KUBECONFIG=~/.kube/config"
fi

# Also make it available for root
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Step 7: Deploy NVIDIA Device Plugin
print_step "Deploying NVIDIA Device Plugin..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: gpu-operator
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: gpu-operator
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.14.3
        name: nvidia-device-plugin-ctr
        env:
        - name: FAIL_ON_INIT_ERROR
          value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
EOF

print_step "✓ NVIDIA Device Plugin deployed"

# Step 8: Wait for device plugin to be ready
print_step "Waiting for NVIDIA Device Plugin to be ready..."
sleep 10

kubectl wait --for=condition=ready pod \
    -l name=nvidia-device-plugin-ds \
    -n gpu-operator \
    --timeout=120s || true

# Step 9: Verify GPU availability in Kubernetes
print_step "Verifying GPU availability in Kubernetes..."

GPU_COUNT=$(kubectl get nodes -o json | \
    jq -r '.items[].status.capacity."nvidia.com/gpu"' | \
    grep -v null | head -1)

if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" != "0" ]; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              K3s with GPU Support Ready!                      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}GPU Availability:${NC}"
    kubectl get nodes -o json | \
        jq -r '.items[] | "\(.metadata.name): \(.status.capacity."nvidia.com/gpu" // "0") GPU(s)"'
    echo ""
    echo -e "${BLUE}Node Resources:${NC}"
    kubectl describe node | grep -A 10 "Capacity:" | head -15
else
    print_warning "GPU not detected in Kubernetes"
    echo "This might take a minute to appear. Check with:"
    echo "  kubectl get nodes -o json | jq '.items[].status.capacity'"
fi

echo ""
echo -e "${BLUE}Quick Commands:${NC}"
echo "  kubectl get nodes                     # List nodes"
echo "  kubectl get pods -A                   # List all pods"
echo "  kubectl describe node                 # Show node details"
echo "  kubectl run gpu-test --image=nvidia/cuda:12.0.0-base-ubuntu22.04 --restart=Never --rm -it -- nvidia-smi"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Deploy your vLLM workload"
echo "  2. See: ../kubernetes/ for manifests"
echo "  3. Run: kubectl apply -k ../kubernetes/"
echo ""

# Save installation info
cat > /root/k3s-install-info.txt <<EOF
K3s Installation Complete
Date: $(date)
Hostname: $(hostname)
K3s Version: $(k3s --version | head -1)
NVIDIA Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU Count: ${GPU_COUNT:-0}
Kubeconfig: /etc/rancher/k3s/k3s.yaml

Quick Test:
  kubectl run gpu-test --image=nvidia/cuda:12.0.0-base-ubuntu22.04 --restart=Never --rm -it -- nvidia-smi
EOF

print_step "Installation info saved to: /root/k3s-install-info.txt"
