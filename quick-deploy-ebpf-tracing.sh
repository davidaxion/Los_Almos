#!/bin/bash
set -e

# Quick Deploy: vLLM + eBPF Tracing on AWS
# Single EC2 instance with K3s + GPU + eBPF sidecar

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Quick Deploy: vLLM + eBPF Tracing on AWS                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will deploy:"
echo "  - 1x g4dn.xlarge (T4 GPU) EC2 instance"
echo "  - K3s (lightweight Kubernetes)"
echo "  - vLLM inference server"
echo "  - eBPF tracing sidecar"
echo "  - Shared volume for traces"
echo ""
echo "Estimated cost: ~$0.53/hour"
echo ""

read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Aborted."
    exit 0
fi

# Configuration
INSTANCE_TYPE="g4dn.xlarge"
REGION="${AWS_REGION:-us-west-2}"
KEY_NAME="${SSH_KEY_NAME:-los-alamos-key}"
SECURITY_GROUP_NAME="ebpf-tracing-sg"
INSTANCE_NAME="ebpf-tracing-instance"

echo ""
echo "🔍 Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Install: https://aws.amazon.com/cli/"
    exit 1
fi

# Check SSH key
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

# Get default VPC
echo ""
echo "🔍 Finding default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "❌ No default VPC found. Creating one..."
    VPC_ID=$(aws ec2 create-default-vpc --region $REGION --query "Vpc.VpcId" --output text)
fi

echo "✅ Using VPC: $VPC_ID"

# Create/Get Security Group
echo ""
echo "🔒 Setting up security group..."
SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "Creating security group..."
    SG_ID=$(aws ec2 create-security-group --region $REGION \
        --group-name $SECURITY_GROUP_NAME \
        --description "Security group for eBPF tracing" \
        --vpc-id $VPC_ID \
        --query "GroupId" --output text)

    # Add rules
    aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 || true
    aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 8000 --cidr 0.0.0.0/0 || true
    aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG_ID --protocol tcp --port 6443 --cidr 0.0.0.0/0 || true

    echo "✅ Security group created: $SG_ID"
else
    echo "✅ Using existing security group: $SG_ID"
fi

# Create/Import SSH key
echo ""
echo "🔑 Setting up SSH key..."
aws ec2 import-key-pair --region $REGION --key-name $KEY_NAME --public-key-material fileb://~/.ssh/id_rsa.pub 2>/dev/null || echo "Key already exists"

# Find latest Deep Learning AMI
echo ""
echo "🔍 Finding Deep Learning AMI..."
AMI_ID=$(aws ec2 describe-images --region $REGION \
    --owners amazon \
    --filters "Name=name,Values=Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 20.04)*" \
              "Name=state,Values=available" \
    --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
    --output text)

echo "✅ Using AMI: $AMI_ID"

# Create user data script
cat > /tmp/user-data-ebpf.sh <<'EOF'
#!/bin/bash
set -e

echo "=========================================="
echo "Setting up eBPF Tracing Environment"
echo "=========================================="

# Update system
apt-get update
apt-get install -y curl git

# Install K3s (lightweight Kubernetes)
echo "Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -

# Wait for K3s to be ready
sleep 30
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install NVIDIA device plugin for K3s
echo "Installing NVIDIA device plugin..."
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml

# Clone Los_Alamos repo
cd /home/ubuntu
git clone https://github.com/davidaxion/Los_Almos.git
chown -R ubuntu:ubuntu Los_Almos

# Create kubeconfig for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Install bpftrace for eBPF
apt-get install -y bpftrace linux-headers-$(uname -r)

# Create welcome message
cat > /etc/motd <<'MOTD'
╔════════════════════════════════════════════════════════════════╗
║          eBPF Tracing Environment - Ready!                     ║
╚════════════════════════════════════════════════════════════════╝

🖥️  ENVIRONMENT
  K3s (Kubernetes):    Running
  NVIDIA GPU:          Available
  eBPF:                Installed

📦 DEPLOY vLLM + eBPF SIDECAR
  cd Los_Almos/shared/research/k3s-vllm-tracing
  kubectl apply -f kubernetes/

📊 CHECK STATUS
  kubectl get pods -n vllm-tracing
  kubectl logs -n vllm-tracing <pod-name> -c ebpf-tracer

📁 ACCESS TRACES
  kubectl exec -n vllm-tracing <pod-name> -c ebpf-tracer -- ls /traces

🔧 MANUAL eBPF TRACING
  # SSH into container
  kubectl exec -it -n vllm-tracing <pod-name> -c ebpf-tracer -- /bin/bash

  # Run trace
  cd /opt/ebpf
  ./run_trace.sh --kernel python test.py

MOTD

echo "=========================================="
echo "Setup complete!"
echo "=========================================="
EOF

# Launch instance
echo ""
echo "🚀 Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances --region $REGION \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --user-data file:///tmp/user-data-ebpf.sh \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=100,VolumeType=gp3}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)

echo "✅ Instance launched: $INSTANCE_ID"

# Wait for instance to be running
echo ""
echo "⏱️  Waiting for instance to be running..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "✅ Instance running at: $PUBLIC_IP"

# Save connection info
cat > ebpf-tracing-connection.txt <<CONN
╔════════════════════════════════════════════════════════════════╗
║          eBPF Tracing Environment - Connection Info            ║
╚════════════════════════════════════════════════════════════════╝

Instance ID: $INSTANCE_ID
Public IP:   $PUBLIC_IP
Region:      $REGION

🔗 SSH CONNECTION
────────────────────────────────────────────────────────────────
ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP

⏱️  WAIT 5-10 MINUTES for initialization to complete

✅ VERIFY SETUP
────────────────────────────────────────────────────────────────
# After SSH:
kubectl get nodes
kubectl get pods --all-namespaces
nvidia-smi

📦 DEPLOY vLLM WITH eBPF SIDECAR
────────────────────────────────────────────────────────────────
cd Los_Almos/shared/research/k3s-vllm-tracing

# Create namespace and storage
kubectl apply -f kubernetes/00-namespace.yaml
kubectl apply -f kubernetes/01-storage.yaml
kubectl apply -f kubernetes/02-serviceaccount.yaml

# Deploy vLLM with eBPF sidecar
kubectl apply -f kubernetes/03-vllm-deployment.yaml
kubectl apply -f kubernetes/04-service.yaml

# Watch deployment
kubectl get pods -n vllm-tracing -w

📊 VIEW eBPF TRACES
────────────────────────────────────────────────────────────────
# Get pod name
POD=\$(kubectl get pods -n vllm-tracing -o name | head -1 | cut -d/ -f2)

# View eBPF tracer logs
kubectl logs -n vllm-tracing \$POD -c ebpf-tracer -f

# Access traces directly
kubectl exec -n vllm-tracing \$POD -c ebpf-tracer -- ls -lh /traces

# Copy traces locally
kubectl cp vllm-tracing/\$POD:/traces ./traces -c ebpf-tracer

🧪 TEST INFERENCE
────────────────────────────────────────────────────────────────
# From your local machine (after vLLM is ready):
curl http://$PUBLIC_IP:8000/v1/completions \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "meta-llama/Llama-2-7b-hf",
    "prompt": "Once upon a time",
    "max_tokens": 50
  }'

🧹 CLEANUP
────────────────────────────────────────────────────────────────
aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID

💰 COST: ~\$0.53/hour
CONN

cat ebpf-tracing-connection.txt

echo ""
echo "💾 Connection info saved to: ebpf-tracing-connection.txt"
echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Wait 5-10 minutes for initialization"
echo "  2. SSH: ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP"
echo "  3. Deploy: kubectl apply -f Los_Almos/shared/research/k3s-vllm-tracing/kubernetes/"
echo "  4. Watch traces: kubectl logs -n vllm-tracing <pod> -c ebpf-tracer -f"
echo ""
