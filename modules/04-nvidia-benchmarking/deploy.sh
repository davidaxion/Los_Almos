#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Module 4: NVIDIA GPU Benchmarking Deployment              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will deploy a GPU instance for performance benchmarking."
echo ""
echo "Available GPU types:"
echo "  - g4dn.xlarge    T4   (~\$0.53/hr)  - Best for learning"
echo "  - g6.2xlarge     L4   (~\$1.10/hr)  - Better performance"
echo "  - g5.xlarge      A10G (~\$1.01/hr)  - Training-focused"
echo "  - p3.2xlarge     V100 (~\$3.06/hr)  - High performance"
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
# NVIDIA GPU Benchmarking Configuration

project_name        = "nvidia-benchmark"
aws_region          = "us-west-2"

# GPU Selection (change this to test different GPUs!)
instance_type       = "g4dn.xlarge"   # T4 GPU (~\$0.53/hr)

# Other options:
# instance_type = "g6.2xlarge"    # L4 GPU (~\$1.10/hr)
# instance_type = "g5.xlarge"     # A10G GPU (~\$1.01/hr)
# instance_type = "p3.2xlarge"    # V100 GPU (~\$3.06/hr)

# Security (IMPORTANT: Restrict to your IP!)
ssh_allowed_cidr    = "0.0.0.0/0"  # WARNING: Open to all

# Storage
root_volume_size    = 100  # GB
EOF
    echo "✅ Created terraform.tfvars"
    echo ""
    echo "💡 To benchmark different GPUs:"
    echo "   1. Edit terraform.tfvars and change instance_type"
    echo "   2. Run: terraform apply"
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
read -p "🚀 Deploy benchmarking instance? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply configuration
echo ""
echo "🚀 Deploying infrastructure (this will take ~5-10 minutes)..."
terraform apply -auto-approve

# Display next steps
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Complete! 🎉                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

terraform output next_steps

echo ""
echo "💡 Quick Commands:"
echo "   SSH:              ssh -i ~/.ssh/id_rsa ubuntu@\$(terraform output -raw instance_public_ip)"
echo "   Run benchmarks:   (after SSH) cd ~/benchmarks && ./run_all_benchmarks.sh"
echo "   Destroy:          terraform destroy"
echo ""
echo "📚 See README.md for detailed benchmarking guide"
echo ""
