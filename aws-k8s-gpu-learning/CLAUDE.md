# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a complete AWS EKS-based GPU learning environment designed for experimenting with GPU computing, vLLM, Slurm, and ML tools. The architecture consists of:

- **EKS Cluster**: Managed Kubernetes cluster with GPU-enabled nodes (default: g4dn.xlarge with NVIDIA T4)
- **NVIDIA Device Plugin**: Manages GPU resource allocation in Kubernetes
- **GPU Development Pod**: CUDA-enabled container with SSH access, ML frameworks (PyTorch, Transformers, vLLM), and development tools
- **LoadBalancer Service**: Exposes SSH (port 22) and Jupyter (port 8888) for external access

## Core Deployment Workflow

### Standard Deployment Sequence (5 Steps)

```bash
# 1. Deploy EKS cluster with GPU nodes (~15-20 minutes)
./scripts/deploy-cluster.sh

# 2. Setup SSH keys in Kubernetes secret
./scripts/setup-ssh-keys.sh

# 3. Deploy GPU pod
kubectl apply -f k8s-manifests/gpu-pod-enhanced.yaml
kubectl wait --for=condition=ready pod/gpu-dev-pod-enhanced --timeout=600s

# 4. Verify status
./scripts/check-status.sh

# 5. Connect via SSH
./scripts/connect-ssh.sh
```

### Cleanup
```bash
./scripts/cleanup.sh  # Deletes entire cluster - critical to avoid AWS costs
```

## Key Configuration Parameters

### Cluster Deployment (scripts/deploy-cluster.sh)

Control via environment variables:
- `CLUSTER_NAME` (default: gpu-learning-cluster)
- `AWS_REGION` (default: us-west-2)
- `NODE_TYPE` (default: g4dn.xlarge) - Change for different GPU types:
  - `g4dn.xlarge`: 1 T4 GPU, 4 vCPUs, 16 GB RAM
  - `g4dn.2xlarge`: 1 T4 GPU, 8 vCPUs, 32 GB RAM
  - `g4dn.12xlarge`: 4 T4 GPUs, 48 vCPUs, 192 GB RAM
  - `p3.2xlarge`: 1 V100 GPU, 8 vCPUs, 61 GB RAM
- `MIN_NODES`, `MAX_NODES`, `DESIRED_NODES`

### GPU Pod Resources (k8s-manifests/gpu-pod-enhanced.yaml)

GPU allocation controlled in the Pod spec:
```yaml
resources:
  limits:
    nvidia.com/gpu: 1  # Change this for multiple GPUs
    memory: "16Gi"
    cpu: "4"
```

## Architecture Details

### SSH Access Pattern

1. **SSH Key Storage**: User's public key stored in Kubernetes secret `gpu-dev-ssh-keys`
2. **Service Exposure**: LoadBalancer service `gpu-dev-ssh-enhanced` assigns external hostname/IP
3. **Connection Flow**:
   - `connect-ssh.sh` retrieves LoadBalancer address dynamically
   - Waits for LoadBalancer provisioning (can take several minutes on first deployment)
   - Connects with SSH key authentication (no password)

### Pod Initialization Process

The enhanced GPU pod uses a ConfigMap-based setup script that:
1. Installs system packages (SSH server, dev tools)
2. Configures SSH for root login with public key auth
3. Installs Python ML packages (PyTorch, Transformers, vLLM, Jupyter)
4. Sets up workspace directory at `/workspace`
5. Starts SSH daemon

This setup runs on every pod start and takes 5-10 minutes on first launch.

### GPU Resource Management

- **NVIDIA Device Plugin**: Deployed as DaemonSet in `kube-system` namespace, exposes GPUs as `nvidia.com/gpu` resource
- **GPU Discovery**: Pods request GPUs via resource limits, plugin handles scheduling and device exposure
- **Environment Variables**: `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES=compute,utility` enable CUDA access

## Common Development Tasks

### Testing GPU Functionality

```bash
# From local machine (executes tests remotely)
./scripts/test-gpu.sh

# Inside the pod
python3 << EOF
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
EOF
```

### Modifying Pod Configuration

When changing `k8s-manifests/gpu-pod-enhanced.yaml`:
```bash
kubectl delete pod gpu-dev-pod-enhanced
kubectl apply -f k8s-manifests/gpu-pod-enhanced.yaml
kubectl wait --for=condition=ready pod/gpu-dev-pod-enhanced --timeout=600s
```

### Adding Custom Docker Image

Build custom image instead of using stock NVIDIA CUDA image:
```bash
cd docker
./build-and-push.sh  # Builds and pushes to ECR

# Update k8s-manifests/gpu-pod-enhanced.yaml image field:
# image: <account-id>.dkr.ecr.<region>.amazonaws.com/gpu-dev-env:latest
```

### Copying Files to Pod

```bash
# Copy to pod
kubectl cp local-file.py gpu-dev-pod-enhanced:/workspace/

# Copy from pod
kubectl cp gpu-dev-pod-enhanced:/workspace/output.txt ./output.txt
```

## Troubleshooting Patterns

### Pod Stuck in Pending
- **Cause**: No GPU available on nodes
- **Check**: `kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds`
- **Fix**: Reinstall NVIDIA plugin (commands in README.md)

### LoadBalancer Pending
- **Cause**: AWS provisioning delay or IAM permission issues
- **Check**: `kubectl describe svc gpu-dev-ssh-enhanced`
- **Wait**: Can take 3-5 minutes on initial creation

### SSH Connection Refused
- **Cause**: Pod not fully initialized or SSH keys not mounted
- **Check**:
  - `kubectl logs gpu-dev-pod-enhanced` (look for "Starting SSH service")
  - `kubectl get secret gpu-dev-ssh-keys`
- **Fix**: Re-run `./scripts/setup-ssh-keys.sh`

### GPU Not Detected in Pod
- **Cause**: NVIDIA plugin not running or GPU not requested in pod spec
- **Check**: `kubectl get nodes -o yaml | grep -A 5 allocatable` (should show `nvidia.com/gpu`)
- **Fix**: Verify pod has `resources.limits.nvidia.com/gpu: 1` set

## Cost Management

**Critical**: This environment incurs ~$0.65/hour (~$470/month if left running)

- Always run `./scripts/cleanup.sh` when finished
- Consider using spot instances: Add `--spot` to eksctl command in `deploy-cluster.sh`
- Use smaller instances for testing (g4dn.xlarge is minimum for GPU)

## Script Reference

| Script | Purpose | Key Functions |
|--------|---------|---------------|
| `deploy-cluster.sh` | Creates EKS cluster | Runs `eksctl create cluster`, installs NVIDIA plugin, verifies GPU availability |
| `setup-ssh-keys.sh` | Configures SSH access | Creates Kubernetes secret from `~/.ssh/id_rsa.pub` |
| `connect-ssh.sh` | SSH into pod | Retrieves LoadBalancer address, waits for availability, connects with SSH key |
| `check-status.sh` | Diagnose environment | Checks cluster, nodes, NVIDIA plugin, pod status, SSH service, GPU allocation |
| `test-gpu.sh` | Verify GPU works | Executes nvidia-smi and PyTorch GPU tests inside pod |
| `cleanup.sh` | Delete all resources | Runs `eksctl delete cluster` with confirmation |

## Working with vLLM

vLLM is pre-installed in the enhanced pod for efficient LLM inference:

```python
from vllm import LLM, SamplingParams

# Initialize model (first run downloads model)
llm = LLM(
    model="facebook/opt-125m",  # Or larger models
    gpu_memory_utilization=0.8,
    max_model_len=512
)

# Generate
sampling_params = SamplingParams(temperature=0.8, top_p=0.95, max_tokens=100)
outputs = llm.generate(["Your prompt here"], sampling_params)
```

Models download on first use and cache in pod storage (emptyDir with 50Gi limit).

## Setting up Slurm

Slurm is not pre-installed but can be configured inside the pod:

```bash
apt-get install -y slurm-wlm
# Full configuration provided in README.md section "Installing Slurm (Optional)"
```

The provided configuration sets up a single-node cluster with GPU resource tracking (`Gres=gpu:1`).

## Prerequisites

This project assumes:
- AWS CLI configured with valid credentials (`aws sts get-caller-identity` succeeds)
- `eksctl` installed for EKS cluster management
- `kubectl` installed for Kubernetes operations
- SSH key pair exists at `~/.ssh/id_rsa` (generated by `setup-ssh-keys.sh` if missing)
- IAM permissions for EC2, EKS, VPC, IAM role creation

## Important Files

- `k8s-manifests/gpu-pod-enhanced.yaml`: Main pod definition with ConfigMap for setup
- `k8s-manifests/gpu-pod.yaml`: Basic version without enhanced tooling
- `docker/Dockerfile`: Custom image with all ML tools pre-installed (optional alternative to ConfigMap setup)
- `examples/test-pytorch.py`: PyTorch GPU benchmark script
- `examples/test-vllm.py`: vLLM inference demo script
