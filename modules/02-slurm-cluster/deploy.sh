#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Module 2: SLURM Cluster Deployment                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will deploy:"
echo "  - 1x Head Node (g4dn.xlarge with T4 GPU)"
echo "  - 2x Worker Nodes (g4dn.xlarge with T4 GPU)"
echo "  - Shared EFS storage"
echo "  - SLURM job scheduler"
echo ""
echo "Estimated cost: ~\$1.60/hour (~\$40/day)"
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
# Los Alamos SLURM Cluster Configuration

project_name  = "los-alamos-slurm"
environment   = "dev"
aws_region    = "us-west-2"

# Instance types (upgrade to g6.2xlarge for L4 GPUs)
head_node_instance_type   = "g4dn.xlarge"   # 1x T4 GPU, ~\$0.53/hr
worker_node_instance_type = "g4dn.xlarge"   # 1x T4 GPU, ~\$0.53/hr
worker_node_count         = 2               # Total: 3 GPUs

# Security (IMPORTANT: Restrict to your IP for production!)
ssh_allowed_cidr = "0.0.0.0/0"  # WARNING: Open to all - change this!

# Storage
s3_model_bucket = "littleboy-dev-models-752105082763"  # Existing S3 bucket
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
read -p "🚀 Deploy SLURM cluster? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply configuration
echo ""
echo "🚀 Deploying infrastructure (this will take ~10-15 minutes)..."
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
echo "💡 Quick Commands:"
echo "   View cluster info:  terraform output"
echo "   SSH to head node:   ssh -i ~/.ssh/id_rsa ubuntu@\$(terraform output -raw head_node_public_ip)"
echo "   Destroy cluster:    terraform destroy"
echo ""
echo "📚 See README.md for exercises and learning materials"
echo ""
