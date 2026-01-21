# Quick Start Guide

Get up and running in 5 simple steps!

## Prerequisites Check

```bash
# Check AWS CLI
aws --version && aws sts get-caller-identity

# Check eksctl
eksctl version

# Check kubectl
kubectl version --client

# Check SSH key
ls ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096
```

## 5-Step Deployment

### 1. Deploy Cluster (~15 minutes)

```bash
cd aws-k8s-gpu-learning
chmod +x scripts/*.sh
./scripts/deploy-cluster.sh
```

### 2. Setup SSH Keys (~1 minute)

```bash
./scripts/setup-ssh-keys.sh
```

### 3. Deploy GPU Pod (~5 minutes)

```bash
kubectl apply -f k8s-manifests/gpu-pod-enhanced.yaml
kubectl wait --for=condition=ready pod/gpu-dev-pod-enhanced --timeout=600s
```

### 4. Check Status

```bash
./scripts/check-status.sh
```

### 5. Connect!

```bash
./scripts/connect-ssh.sh

# Inside the pod:
nvidia-smi
python3 -c "import torch; print(f'CUDA: {torch.cuda.is_available()}')"
```

## Quick Test

```bash
# From your local machine
./scripts/test-gpu.sh
```

## Clean Up When Done

```bash
./scripts/cleanup.sh
```

## Costs

- **~$0.65/hour** or **~$470/month** if left running
- **Always cleanup** when not in use!

## Troubleshooting

```bash
# Pod not starting?
kubectl describe pod gpu-dev-pod-enhanced
kubectl logs gpu-dev-pod-enhanced

# Can't connect?
kubectl get svc gpu-dev-ssh-enhanced
kubectl get secret gpu-dev-ssh-keys

# GPU not working?
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
```

## What's Installed

- NVIDIA CUDA 12.3.1
- PyTorch with GPU support
- Transformers (Hugging Face)
- vLLM for LLM inference
- Jupyter Lab
- Git, vim, tmux, htop
- And more!

See full README.md for detailed documentation.
