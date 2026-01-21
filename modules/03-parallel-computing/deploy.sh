#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Module 3: Distributed GPU Training Deployment             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will deploy:"
echo "  - 2x GPU Nodes (g4dn.2xlarge with T4 GPUs)"
echo "  - Configured for distributed training"
echo "  - PyTorch DDP examples included"
echo ""
echo "Estimated cost: ~\$1.50/hour (~\$36/day)"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Install: https://www.terraform.io/downloads"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Install: https://aws.amazon.com/cli/"
    exit 1
fi

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "⚠️  No SSH key found at ~/.ssh/id_rsa.pub"
    read -p "Generate new SSH key? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        echo "✅ SSH key generated"
    else
        echo "❌ SSH key required"
        exit 1
    fi
fi

echo "✅ Prerequisites OK"
echo ""

# Navigate to terraform directory
cd terraform

# Create terraform.tfvars if it doesn't exist
if [ ! -f terraform.tfvars ]; then
    echo "📝 Creating terraform.tfvars..."
    cat > terraform.tfvars <<EOF
# Distributed GPU Training Configuration

project_name        = "parallel-gpu"
aws_region          = "us-west-2"

# Instance configuration
instance_type       = "g4dn.2xlarge"   # 1x T4 GPU, 8 vCPUs, 32GB RAM (~\$0.75/hr each)
num_nodes           = 2                # Number of GPU nodes

# Upgrade options:
# g6.2xlarge   - 1x L4 GPU, 8 vCPUs, 32GB RAM (~\$1.10/hr) - Better performance
# g4dn.12xlarge - 4x T4 GPUs, 48 vCPUs, 192GB RAM (~\$3.91/hr) - Multiple GPUs per node

# Security (IMPORTANT: Restrict to your IP!)
ssh_allowed_cidr    = "0.0.0.0/0"  # WARNING: Open to all - change this!

# Storage
root_volume_size    = 100  # GB
EOF
    echo "✅ Created terraform.tfvars (review and customize as needed)"
    echo ""
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init
echo ""

# Plan deployment
echo "📋 Planning deployment..."
terraform plan
echo ""

# Confirm deployment
read -p "🚀 Deploy distributed training environment? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply configuration
echo ""
echo "🚀 Deploying infrastructure (this will take ~5-10 minutes)..."
terraform apply -auto-approve

# Save connection info
echo ""
echo "💾 Saving connection information..."
terraform output -json > cluster-info.json

# Display next steps
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Complete! 🎉                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

terraform output next_steps

echo ""
echo "📄 Connection info saved to: terraform/cluster-info.json"
echo ""
echo "💡 Quick Start:"
echo "   1. Wait 5-10 minutes for initialization"
echo "   2. SSH to both nodes (see output above)"
echo "   3. Run distributed training (instructions in output)"
echo ""
echo "📚 See README.md for detailed exercises and examples"
echo ""
