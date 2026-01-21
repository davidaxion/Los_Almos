#!/bin/bash
set -e

# Quick deployment script for Los Alamos SLURM GPU Cluster
# This script automates the deployment process

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║          Los Alamos SLURM GPU Cluster - Quick Deployment Script           ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Install from: https://terraform.io/downloads"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Install from: https://aws.amazon.com/cli/"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Run: aws configure"
    exit 1
fi

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "⚠️  SSH public key not found at ~/.ssh/id_rsa.pub"
    read -p "Generate new SSH key? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        echo "✅ SSH key generated"
    else
        echo "❌ SSH key required for deployment"
        exit 1
    fi
fi

echo "✅ All prerequisites met"
echo

# Check for terraform.tfvars
if [ ! -f terraform.tfvars ]; then
    echo "⚠️  terraform.tfvars not found"
    echo
    read -p "Create terraform.tfvars from example? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp terraform.tfvars.example terraform.tfvars
        echo "✅ terraform.tfvars created"
        echo
        echo "⚠️  IMPORTANT: Edit terraform.tfvars to:"
        echo "   1. Restrict ssh_allowed_cidr to your IP"
        echo "   2. Adjust instance types if needed"
        echo "   3. Set worker_node_count (2-4)"
        echo
        read -p "Press Enter after editing terraform.tfvars..."
    else
        echo "❌ terraform.tfvars required for deployment"
        exit 1
    fi
fi

# Initialize Terraform
echo "🚀 Initializing Terraform..."
terraform init
echo

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate
echo

# Show plan
echo "📋 Showing deployment plan..."
terraform plan
echo

# Confirm deployment
read -p "🚀 Deploy cluster? This will create AWS resources. (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

# Deploy
echo "🚀 Deploying SLURM GPU cluster..."
echo "⏱️  This will take 10-15 minutes..."
terraform apply -auto-approve

# Save outputs
echo
echo "💾 Saving cluster information..."
terraform output -json > cluster-info.json
terraform output next_steps > CLUSTER_ACCESS.txt

# Display connection info
echo
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                     ✅ Deployment Complete!                                ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo

# Show next steps
terraform output next_steps

# Get head node IP
HEAD_IP=$(terraform output -raw head_node_public_ip)

echo
echo "📁 Cluster information saved to:"
echo "   - cluster-info.json (full details)"
echo "   - CLUSTER_ACCESS.txt (quick reference)"
echo
echo "⏱️  IMPORTANT: Wait 5-10 minutes for node initialization before connecting"
echo
echo "🔗 Quick connect:"
echo "   ssh -i ~/.ssh/id_rsa ubuntu@$HEAD_IP"
echo

# Optional: Test connection
read -p "Test SSH connection now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Testing connection (will retry for up to 2 minutes)..."
    for i in {1..24}; do
        if ssh -i ~/.ssh/id_rsa -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$HEAD_IP "echo Connection successful" 2>/dev/null; then
            echo "✅ SSH connection successful!"
            echo
            echo "To connect: ssh -i ~/.ssh/id_rsa ubuntu@$HEAD_IP"
            break
        else
            echo "Attempt $i/24: Node still initializing..."
            sleep 5
        fi
    done
fi

echo
echo "🎉 Setup complete! Enjoy your SLURM GPU cluster!"
echo
