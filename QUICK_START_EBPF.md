# Quick Start: eBPF Tracing on AWS

Deploy vLLM with eBPF sidecar tracing in **5 minutes** on a single AWS GPU instance.

## 🎯 What You Get

- ✅ Single GPU instance (g4dn.xlarge with T4 GPU)
- ✅ K3s (lightweight Kubernetes)
- ✅ vLLM inference server
- ✅ eBPF tracing sidecar (captures all GPU operations)
- ✅ Shared volume for trace files
- ✅ Cost: ~$0.53/hour

## 🚀 One-Command Deploy

```bash
./quick-deploy-ebpf-tracing.sh
```

That's it! The script will:
1. Launch EC2 instance with GPU
2. Install K3s + NVIDIA drivers
3. Set up eBPF tools
4. Clone this repo on the instance
5. Give you connection instructions

## 📋 Step-by-Step

### 1. Deploy Infrastructure

```bash
# From Los_Alamos directory
./quick-deploy-ebpf-tracing.sh
```

Wait 5-10 minutes for initialization.

### 2. SSH into Instance

```bash
# From output
ssh -i ~/.ssh/id_rsa ubuntu@<PUBLIC_IP>
```

### 3. Verify Setup

```bash
# Check K3s is running
kubectl get nodes

# Check GPU is available
nvidia-smi

# Check eBPF is installed
sudo bpftrace --version
```

### 4. Deploy vLLM + eBPF Sidecar

```bash
cd Los_Almos/shared/research/k3s-vllm-tracing

# Deploy everything
kubectl apply -f kubernetes/

# Watch pods start
kubectl get pods -n vllm-tracing -w
```

Wait ~5 minutes for vLLM to download model and start.

### 5. View eBPF Traces

```bash
# Get pod name
POD=$(kubectl get pods -n vllm-tracing -o name | head -1 | cut -d/ -f2)

# Stream eBPF tracer logs (live tracing!)
kubectl logs -n vllm-tracing $POD -c ebpf-tracer -f
```

You'll see **real-time CUDA traces** as vLLM runs!

### 6. Send Test Request

```bash
# From your local machine
curl http://<PUBLIC_IP>:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-2-7b-hf",
    "prompt": "Explain GPU inference in one sentence:",
    "max_tokens": 50
  }'
```

Watch the eBPF logs to see **all CUDA operations** for this inference request!

### 7. Access Trace Files

```bash
# List traces
kubectl exec -n vllm-tracing $POD -c ebpf-tracer -- ls -lh /traces

# Copy traces to local machine
kubectl cp vllm-tracing/$POD:/traces ./traces -c ebpf-tracer

# Analyze locally
cd traces
ls -la
```

## 📊 What Gets Traced

The eBPF sidecar captures:

- **CUDA API calls**: cuInit, cuMemAlloc, cuLaunchKernel, etc.
- **Memory operations**: Allocations, transfers (H2D, D2H)
- **Kernel launches**: Every GPU kernel with timing
- **Context switches**: GPU context management
- **Driver calls**: IOCTL calls to nvidia.ko

## 🔧 Architecture

```
┌─────────────────────────────────────────┐
│         EC2 Instance (g4dn.xlarge)      │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │         K3s Pod                   │  │
│  │                                   │  │
│  │  ┌──────────┐   ┌──────────────┐ │  │
│  │  │  vLLM    │   │ eBPF Tracer  │ │  │
│  │  │ Container│   │  Container   │ │  │
│  │  │          │   │              │ │  │
│  │  │ • Python │   │ • bpftrace   │ │  │
│  │  │ • vLLM   │   │ • BCC        │ │  │
│  │  │ • Model  │   │ • Hooks      │ │  │
│  │  └────┬─────┘   └──────┬───────┘ │  │
│  │       │                 │         │  │
│  │       └─────hostPID─────┘         │  │
│  │       │                 │         │  │
│  │       └────/traces──────┘         │  │
│  │                                   │  │
│  └───────────────────────────────────┘  │
│                                         │
│         ┌─────────────────┐             │
│         │   NVIDIA GPU    │             │
│         │   (T4 - 16GB)   │             │
│         └─────────────────┘             │
└─────────────────────────────────────────┘
```

**Key Features:**
- `hostPID: true` - Sidecar can attach to vLLM process
- Privileged mode - Required for eBPF
- Shared `/traces` volume - Store trace files
- Host `/sys` mount - eBPF needs kernel access

## 🎓 Use Cases

### 1. Understanding Inference Pipeline

```bash
# Send request
curl http://<IP>:8000/v1/completions -d '{"prompt": "Hello", "max_tokens": 10}'

# Watch eBPF logs to see:
# 1. cuMemAlloc (input buffers)
# 2. cuMemcpyHtoD (copy input to GPU)
# 3. cuLaunchKernel (attention, MLP, etc.)
# 4. cuMemcpyDtoH (copy output from GPU)
# 5. cuMemFree (cleanup)
```

### 2. Memory Analysis

```bash
# Filter for memory operations
kubectl logs -n vllm-tracing $POD -c ebpf-tracer | grep -E "cuMem"

# See allocations, transfers, deallocations
```

### 3. Kernel Profiling

```bash
# Filter for kernel launches
kubectl logs -n vllm-tracing $POD -c ebpf-tracer | grep "cuLaunchKernel"

# Count kernels per request
kubectl logs -n vllm-tracing $POD -c ebpf-tracer | grep "cuLaunchKernel" | wc -l
```

### 4. Timeline Analysis

```bash
# Copy traces
kubectl cp vllm-tracing/$POD:/traces ./traces -c ebpf-tracer

# Visualize (if you have visualize_pipeline.py)
python shared/research/libcuda-hooking/tools/visualize_pipeline.py traces/trace_*.jsonl
```

## 🔬 Advanced: Custom eBPF Scripts

### Option 1: Exec into Sidecar

```bash
# Get shell in eBPF container
kubectl exec -it -n vllm-tracing $POD -c ebpf-tracer -- /bin/bash

# Run custom trace
cd /opt/ebpf
./run_trace.sh --kernel python test.py

# Or use bpftrace directly
sudo bpftrace trace_cuda_full.bt
```

### Option 2: Modify Deployment

Edit `kubernetes/03-vllm-deployment.yaml`:

```yaml
- name: ebpf-tracer
  env:
    - name: CUSTOM_TRACE_SCRIPT
      value: "/opt/ebpf/my_custom_trace.bt"
```

### Option 3: Add Your Own Scripts

```bash
# Create ConfigMap with your script
kubectl create configmap custom-trace \
  --from-file=my_trace.bt \
  -n vllm-tracing

# Mount in deployment
# (see k3s-vllm-tracing docs)
```

## 🐛 Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n vllm-tracing $POD

# Check logs
kubectl logs -n vllm-tracing $POD -c vllm
kubectl logs -n vllm-tracing $POD -c ebpf-tracer
```

### eBPF Not Working

```bash
# Check if privileged
kubectl get pod -n vllm-tracing $POD -o yaml | grep privileged

# Check host mounts
kubectl exec -n vllm-tracing $POD -c ebpf-tracer -- ls /sys/kernel/debug

# Check bpftrace
kubectl exec -n vllm-tracing $POD -c ebpf-tracer -- bpftrace --version
```

### No Traces Generated

```bash
# Check if /traces is writable
kubectl exec -n vllm-tracing $POD -c ebpf-tracer -- ls -la /traces

# Check tracer is running
kubectl exec -n vllm-tracing $POD -c ebpf-tracer -- ps aux | grep bpftrace
```

### vLLM Not Loading Model

```bash
# Check HuggingFace token (if using gated models)
kubectl get secret hf-token -n vllm-tracing

# Create if needed
kubectl create secret generic hf-token \
  --from-literal=token=hf_YOUR_TOKEN \
  -n vllm-tracing

# Restart pod
kubectl delete pod -n vllm-tracing $POD
```

## 🧹 Cleanup

```bash
# From your local machine

# Get instance ID from connection file
INSTANCE_ID=$(grep "Instance ID:" ebpf-tracing-connection.txt | awk '{print $3}')

# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-west-2

# Verify termination
aws ec2 describe-instances --instance-ids $INSTANCE_ID --region us-west-2
```

## 💰 Cost Breakdown

| Resource | Cost/Hour | Monthly (24/7) |
|----------|-----------|----------------|
| g4dn.xlarge | $0.526 | ~$380 |
| EBS (100GB) | $0.10/month | $0.10 |
| **Total** | **~$0.53/hr** | **~$380/month** |

**Tips:**
- Stop instance when not using (EBS persists)
- Use Spot instances for 70% savings
- Destroy when done learning

## 📚 Next Steps

1. **Analyze traces**: Use `shared/research/libcuda-hooking/tools/`
2. **Add custom hooks**: See `shared/research/libcuda-hooking/ebpf/KERNEL_HOOKS.md`
3. **Benchmark**: Compare different models/configs
4. **Research**: Design GPU virtualization based on findings

## 🔗 Resources

- **eBPF Tracing Guide**: `shared/research/libcuda-hooking/ebpf/README.md`
- **K3s vLLM Tracing**: `shared/research/k3s-vllm-tracing/README.md`
- **Kernel Hooks**: `shared/research/libcuda-hooking/ebpf/KERNEL_HOOKS.md`
- **Full Documentation**: `shared/research/README.md`

---

**Questions?** Check the research docs or run with `--help` flag.

**Ready to trace?** Run `./quick-deploy-ebpf-tracing.sh` now! 🚀
