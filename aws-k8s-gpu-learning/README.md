# AWS Kubernetes GPU Learning Environment

A complete setup for learning GPU computing, vLLM, Slurm, and other ML tools on AWS EKS with SSH access.

## Overview

This project provides:
- EKS cluster with GPU-enabled nodes (NVIDIA T4 by default)
- GPU pod with SSH access
- Pre-installed tools: PyTorch, Transformers, vLLM, Jupyter, and more
- Easy deployment and management scripts

## Architecture

```
AWS EKS Cluster
├── GPU Node Group (g4dn.xlarge with 1 NVIDIA T4 GPU)
├── NVIDIA Device Plugin (manages GPU allocation)
└── GPU Development Pod
    ├── NVIDIA CUDA 12.3.1
    ├── PyTorch with CUDA support
    ├── vLLM for LLM inference
    ├── SSH access via LoadBalancer
    └── Persistent workspace
```

## Prerequisites

Before starting, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure  # Set up your credentials
   ```

2. **eksctl** - EKS cluster management tool
   ```bash
   # macOS
   brew install eksctl

   # Linux
   curl --location "https://github.com/weksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin
   ```

3. **kubectl** - Kubernetes CLI
   ```bash
   # macOS
   brew install kubectl

   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

4. **SSH keys** - For accessing the GPU pod
   ```bash
   # Generate if you don't have one
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

5. **AWS Credentials** - Proper IAM permissions
   - EC2, EKS, VPC creation permissions
   - IAM role creation permissions

## Cost Estimation

**Important**: Running this environment will incur AWS costs.

Approximate costs (us-west-2 region):
- **g4dn.xlarge** (1 GPU): ~$0.526/hour
- **EKS cluster**: $0.10/hour
- **LoadBalancer**: ~$0.025/hour
- **Total**: ~$0.65/hour or ~$470/month if left running

**Cost-saving tips**:
- Delete the cluster when not using it: `./scripts/cleanup.sh`
- Use spot instances (add `--spot` to eksctl command)
- Choose smaller instance types for testing

## Step-by-Step Deployment

### Step 1: Configure AWS Credentials

```bash
# Verify your AWS credentials
aws sts get-caller-identity

# Output should show your account ID, user, and ARN
```

### Step 2: Deploy the EKS Cluster

```bash
cd aws-k8s-gpu-learning

# Make scripts executable
chmod +x scripts/*.sh
chmod +x docker/*.sh

# Deploy cluster (takes 15-20 minutes)
./scripts/deploy-cluster.sh

# Monitor the deployment
# The script will create:
# - EKS cluster with GPU nodes
# - Install NVIDIA device plugin
# - Configure kubectl
```

**Optional**: Customize deployment:
```bash
# Use different instance type or region
export NODE_TYPE=g4dn.2xlarge  # 1 GPU, more CPU/RAM
export AWS_REGION=us-east-1
export CLUSTER_NAME=my-gpu-cluster

./scripts/deploy-cluster.sh
```

### Step 3: Setup SSH Keys

```bash
# Add your SSH public key to Kubernetes
./scripts/setup-ssh-keys.sh

# This creates a Kubernetes secret with your public key
```

### Step 4: Deploy the GPU Pod

```bash
# Deploy the enhanced GPU development pod
kubectl apply -f k8s-manifests/gpu-pod-enhanced.yaml

# Wait for pod to be ready (may take 5-10 minutes for first-time setup)
kubectl wait --for=condition=ready pod/gpu-dev-pod-enhanced --timeout=600s

# Check status
./scripts/check-status.sh
```

### Step 5: Connect via SSH

```bash
# Connect to the GPU pod
./scripts/connect-ssh.sh

# You should now be in the GPU environment!
# Try:
nvidia-smi
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
```

### Step 6: Test GPU Functionality

```bash
# Run GPU tests (from your local machine)
./scripts/test-gpu.sh

# Or test inside the pod
./scripts/connect-ssh.sh
# Inside the pod:
nvidia-smi
python3 -c "import torch; print(torch.cuda.is_available())"
```

## Using the Environment

### SSH Access

Once connected, you have full root access to a GPU-enabled environment:

```bash
# Check GPU
nvidia-smi

# Python with PyTorch
python3
>>> import torch
>>> torch.cuda.is_available()  # Should return True
>>> torch.cuda.get_device_name(0)  # Show GPU name

# Your workspace
cd /workspace
```

### Running vLLM

```bash
# Example: Run a small model with vLLM
python3 << EOF
from vllm import LLM, SamplingParams

# Load a small model (requires internet connection)
llm = LLM(model="facebook/opt-125m")

prompts = ["Hello, my name is", "The future of AI is"]
sampling_params = SamplingParams(temperature=0.8, top_p=0.95)

outputs = llm.generate(prompts, sampling_params)

for output in outputs:
    print(f"Prompt: {output.prompt}")
    print(f"Generated: {output.outputs[0].text}")
    print()
EOF
```

### Running Jupyter Lab

```bash
# Start Jupyter Lab (inside the pod)
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root &

# Get the LoadBalancer address
kubectl get svc gpu-dev-ssh-enhanced -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access Jupyter at: http://<loadbalancer-address>:8888
# Token is shown in the jupyter lab output
```

### Installing Slurm (Optional)

```bash
# Inside the pod
apt-get update
apt-get install -y slurm-wlm

# Configure slurm (basic single-node setup)
cat > /etc/slurm/slurm.conf << 'EOF'
ClusterName=gpu-cluster
SlurmctldHost=localhost
MpiDefault=none
ProctrackType=proctrack/linuxproc
ReturnToService=2
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid
SlurmdSpoolDir=/var/spool/slurmd
StateSaveLocation=/var/spool/slurmctld
SwitchType=switch/none
TaskPlugin=task/none

# TIMERS
SlurmctldTimeout=300
SlurmdTimeout=300

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres

# LOGGING
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log

# COMPUTE NODES
NodeName=localhost CPUs=4 RealMemory=15000 Gres=gpu:1 State=UNKNOWN
PartitionName=gpu Nodes=localhost Default=YES MaxTime=INFINITE State=UP
EOF

# Create directories
mkdir -p /var/spool/slurmctld /var/spool/slurmd /var/log/slurm

# Start slurm
slurmctld
slurmd

# Test
sinfo
srun --gres=gpu:1 nvidia-smi
```

## Management Scripts

| Script | Description |
|--------|-------------|
| `deploy-cluster.sh` | Deploy EKS cluster with GPU nodes |
| `cleanup.sh` | Delete the entire cluster and resources |
| `setup-ssh-keys.sh` | Configure SSH keys for pod access |
| `connect-ssh.sh` | Connect to the GPU pod via SSH |
| `check-status.sh` | Check the status of all components |
| `test-gpu.sh` | Run GPU tests from outside the pod |

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl describe pod gpu-dev-pod-enhanced

# Check logs
kubectl logs gpu-dev-pod-enhanced

# Common issues:
# - No GPU available: Check if NVIDIA plugin is running
# - Image pull errors: Check ECR permissions
```

### Cannot SSH

```bash
# Check service status
kubectl get svc gpu-dev-ssh-enhanced

# Check if LoadBalancer has external IP/hostname
# If pending, wait a few minutes

# Check SSH keys
kubectl get secret gpu-dev-ssh-keys
kubectl describe secret gpu-dev-ssh-keys
```

### GPU not detected

```bash
# Check NVIDIA plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check node GPU allocation
kubectl get nodes -o yaml | grep -A 5 allocatable

# Reinstall plugin
kubectl delete -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

### Out of memory

```bash
# Check resource usage
kubectl top node
kubectl top pod

# Adjust pod resources in k8s-manifests/gpu-pod-enhanced.yaml
# Increase memory limits under resources.limits.memory
```

## Customization

### Use Different GPU Instance

Edit `scripts/deploy-cluster.sh`:
```bash
# Change NODE_TYPE
export NODE_TYPE=g4dn.2xlarge  # 1 T4 GPU, 8 vCPUs, 32 GB RAM
# or
export NODE_TYPE=p3.2xlarge    # 1 V100 GPU, 8 vCPUs, 61 GB RAM
```

### Add More GPUs

Edit `k8s-manifests/gpu-pod-enhanced.yaml`:
```yaml
resources:
  limits:
    nvidia.com/gpu: 2  # Change to 2 GPUs
```

And use a multi-GPU instance:
```bash
export NODE_TYPE=g4dn.12xlarge  # 4 T4 GPUs
```

### Use Custom Docker Image

Build and push your image:
```bash
cd docker
./build-and-push.sh
```

Then update `k8s-manifests/gpu-pod-enhanced.yaml`:
```yaml
image: <your-account-id>.dkr.ecr.<region>.amazonaws.com/gpu-dev-env:latest
```

## Learning Resources

Once you're in the environment, try:

1. **PyTorch Tutorials**: https://pytorch.org/tutorials/
2. **vLLM Documentation**: https://docs.vllm.ai/
3. **Transformers**: https://huggingface.co/docs/transformers/
4. **CUDA Programming**: https://docs.nvidia.com/cuda/

## Cleanup

**Important**: Don't forget to clean up to avoid charges!

```bash
# Delete the entire cluster
./scripts/cleanup.sh

# Verify deletion
eksctl get cluster --region us-west-2
```

## Project Structure

```
aws-k8s-gpu-learning/
├── README.md
├── scripts/
│   ├── deploy-cluster.sh      # Deploy EKS cluster
│   ├── cleanup.sh             # Delete cluster
│   ├── setup-ssh-keys.sh      # Configure SSH keys
│   ├── connect-ssh.sh         # SSH into pod
│   ├── check-status.sh        # Check environment status
│   └── test-gpu.sh            # Test GPU functionality
├── k8s-manifests/
│   ├── gpu-pod.yaml           # Basic GPU pod
│   └── gpu-pod-enhanced.yaml  # Enhanced pod with all tools
└── docker/
    ├── Dockerfile             # Custom image with all tools
    ├── entrypoint.sh          # Container startup script
    └── build-and-push.sh      # Build and push to ECR
```

## Security Considerations

1. **SSH Keys**: Only your public key is stored in Kubernetes
2. **Network**: LoadBalancer is public but only accepts key-based SSH
3. **IAM**: Use least-privilege IAM roles
4. **Secrets**: Don't commit AWS credentials or secrets

## Next Steps

After getting the environment running:

1. Experiment with different ML models
2. Set up multi-node GPU training
3. Deploy Slurm for job scheduling
4. Try different vLLM configurations
5. Benchmark GPU performance

## Support

For issues:
1. Check `./scripts/check-status.sh` output
2. Review pod logs: `kubectl logs gpu-dev-pod-enhanced`
3. Check AWS console for EKS/EC2 issues

## License

This is a learning environment. Use at your own risk and responsibility.
