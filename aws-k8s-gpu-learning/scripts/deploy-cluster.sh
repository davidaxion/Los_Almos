#!/bin/bash
set -e

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-gpu-learning-cluster}"
REGION="${AWS_REGION:-us-west-2}"
NODE_TYPE="${NODE_TYPE:-g6.2xlarge}"  # 1 GPU (NVIDIA L4), 8 vCPUs, 32 GB RAM
# See GPU_INSTANCES.md for all available instance types
# Popular alternatives: g6.xlarge (L4, 4 vCPU), g6.12xlarge (4x L4), g4dn.xlarge (T4, budget)
MIN_NODES="${MIN_NODES:-1}"
MAX_NODES="${MAX_NODES:-2}"
DESIRED_NODES="${DESIRED_NODES:-1}"

echo "========================================="
echo "Deploying EKS Cluster with GPU Support"
echo "========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Node Type: $NODE_TYPE"
echo "Desired Nodes: $DESIRED_NODES"
echo "========================================="

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v eksctl >/dev/null 2>&1 || { echo "eksctl is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }

# Verify AWS credentials
echo "Verifying AWS credentials..."
aws sts get-caller-identity || { echo "AWS credentials not configured. Run 'aws configure' first." >&2; exit 1; }

# Create EKS cluster
echo "Creating EKS cluster (this will take 15-20 minutes)..."
eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --version 1.28 \
  --nodegroup-name gpu-nodes \
  --node-type "$NODE_TYPE" \
  --nodes "$DESIRED_NODES" \
  --nodes-min "$MIN_NODES" \
  --nodes-max "$MAX_NODES" \
  --node-volume-size 100 \
  --ssh-access \
  --ssh-public-key ~/.ssh/id_rsa.pub \
  --managed \
  --asg-access \
  --external-dns-access \
  --full-ecr-access \
  --alb-ingress-access

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Verify cluster
echo "Verifying cluster..."
kubectl get nodes

# Install NVIDIA device plugin
echo "Installing NVIDIA device plugin..."
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Wait for device plugin to be ready
echo "Waiting for NVIDIA device plugin to be ready..."
kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=300s

# Verify GPU is available
echo "Verifying GPU availability..."
kubectl get nodes "-o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"

echo "========================================="
echo "Cluster deployment complete!"
echo "========================================="
echo "Next steps:"
echo "1. Deploy the GPU pod: kubectl apply -f k8s-manifests/gpu-pod.yaml"
echo "2. Wait for pod to be ready: kubectl wait --for=condition=ready pod/gpu-dev-pod --timeout=300s"
echo "3. Get SSH access: ./scripts/connect-ssh.sh"
echo "========================================="
