#!/bin/bash
set -e

# Module 1: Basic GPU Setup - Quick Deploy Script

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Module 1: Basic GPU Setup - Deployment Script             ║"
echo "╚════════════════════════════════════════════════════════════════╝"

cd terraform

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Install from: https://terraform.io/downloads"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Install from: https://aws.amazon.com/cli/"
    exit 1
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    cat > terraform.tfvars <<EOF
# Module 1: Basic GPU Setup Configuration
project_name        = "basic-gpu-learning"
aws_region          = "us-west-2"
instance_type       = "g4dn.xlarge"  # T4 GPU
root_volume_size    = 50
ssh_allowed_cidr    = "0.0.0.0/0"  # ⚠️  Change to your IP!
ssh_key_name        = ""
ssh_public_key_path = "~/.ssh/id_rsa.pub"
EOF
    echo "✅ Created terraform.tfvars"
fi

# Initialize and deploy
echo "🚀 Initializing Terraform..."
terraform init

echo "📋 Planning deployment..."
terraform plan

read -p "🚀 Deploy instance? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo "🚀 Deploying GPU instance..."
terraform apply -auto-approve

# Show outputs
echo ""
terraform output next_steps

echo ""
echo "💾 Connection info saved to: connection-info.txt"
terraform output -raw ssh_command > connection-info.txt

echo ""
echo "✅ Deployment complete!"
