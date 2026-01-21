# vLLM with eBPF CUDA Tracing on K3s

Real-time CUDA API tracing for vLLM inference workloads using eBPF sidecar pattern on Kubernetes.

## Overview

This project deploys vLLM (Large Language Model inference server) on K3s (lightweight Kubernetes) with a privileged eBPF sidecar container that captures CUDA API calls in real-time. Traces are automatically uploaded to S3 for analysis.

### Key Features

- **Zero-overhead tracing** - eBPF probes with minimal performance impact
- **Automatic trace collection** - Sidecar discovers and attaches to vLLM process
- **S3 integration** - Traces uploaded automatically every 2 minutes
- **Production-ready** - Kubernetes manifests with proper resource limits and health checks
- **One-command deployment** - Automated build, deploy, test, and verify workflow

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         K3s Cluster                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              vllm-tracing namespace                   │ │
│  │                                                       │ │
│  │  ┌─────────────────────────────────────────────────┐ │ │
│  │  │              Pod (hostPID=true)                 │ │ │
│  │  │                                                 │ │ │
│  │  │  ┌──────────────────┐  ┌──────────────────┐    │ │ │
│  │  │  │  vLLM Container  │  │  eBPF Sidecar   │    │ │ │
│  │  │  │                  │  │                  │    │ │ │
│  │  │  │  Llama-2-7b-hf   │  │  bpftrace        │    │ │ │
│  │  │  │  OpenAI API      │  │  CUDA hooks      │    │ │ │
│  │  │  │  :8000           │  │  Process attach  │    │ │ │
│  │  │  │                  │  │                  │    │ │ │
│  │  │  │  ┌────────────┐  │  │  ┌────────────┐ │    │ │ │
│  │  │  │  │   CUDA     │◄─┼──┼─►│   Probes   │ │    │ │ │
│  │  │  │  │   Calls    │  │  │  │  (uprobe)  │ │    │ │ │
│  │  │  │  └────────────┘  │  │  └──────┬─────┘ │    │ │ │
│  │  │  │                  │  │         │       │    │ │ │
│  │  │  └──────────────────┘  │  ┌──────▼─────┐ │    │ │ │
│  │  │                        │  │   Trace    │ │    │ │ │
│  │  │  Shared Volume         │  │   Files    │ │    │ │ │
│  │  │  /traces ◄─────────────┼──┤  (JSONL)   │ │    │ │ │
│  │  │                        │  └──────┬─────┘ │    │ │ │
│  │  │                        │         │       │    │ │ │
│  │  │                        │  ┌──────▼─────┐ │    │ │ │
│  │  │                        │  │  S3 Upload │ │    │ │ │
│  │  │                        │  │  (AWS CLI) │ │    │ │ │
│  │  │                        │  └────────────┘ │    │ │ │
│  │  └─────────────────────────────────────────┘    │ │ │
│  │                                                  │ │ │
│  │  Service: vllm-api (NodePort 30800)             │ │ │
│  └──────────────────────────────────────────────────┘ │ │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
                ┌───────────────────┐
                │    AWS S3         │
                │  littleboy-       │
                │  research-traces/ │
                └───────────────────┘
```

### How It Works

1. **Sidecar Pattern**: Both vLLM and eBPF tracer run in the same pod with `hostPID: true`, allowing the tracer to see vLLM's process
2. **Process Discovery**: Tracer automatically finds vLLM process by name (`pgrep -f "python.*vllm"`)
3. **eBPF Attachment**: bpftrace attaches uprobes to libcuda.so functions in vLLM's address space
4. **Trace Capture**: CUDA API calls (cuInit, cuMemAlloc, cuLaunchKernel, etc.) are logged to JSONL files
5. **Automatic Upload**: Background process uploads completed traces to S3 every 2 minutes
6. **Cleanup**: Local files deleted after successful upload to prevent disk full

## Prerequisites

### Hardware
- NVIDIA GPU (tested with T4, A10, A100)
- 16GB+ RAM
- 50GB+ disk space

### Software
- Ubuntu 22.04
- NVIDIA drivers (≥525.x)
- Docker
- K3s (installed by this project)
- AWS credentials (for S3 upload)

### External Services
- Hugging Face account with Llama-2 access
- AWS S3 bucket

## Quick Start

### 1. Install K3s with GPU Support

```bash
sudo ./infrastructure/k3s-install.sh
```

This installs:
- K3s (lightweight Kubernetes)
- NVIDIA Container Toolkit
- NVIDIA Device Plugin for Kubernetes

### 2. Configure Secrets

```bash
# Hugging Face token (required for Llama-2 model access)
kubectl create namespace vllm-tracing
kubectl create secret generic hf-token \
  --from-literal=token=YOUR_HF_TOKEN \
  -n vllm-tracing

# AWS credentials (for S3 upload)
# Option A: Use instance IAM role (recommended)
# Option B: Use ~/.aws/credentials
# Option C: Set in pod env vars (not recommended for production)
```

### 3. Deploy Everything

```bash
# One-command deployment
./deploy.sh all
```

This will:
1. Build eBPF sidecar Docker image
2. Deploy to K3s (namespace, storage, vLLM pod, service)
3. Wait for vLLM to download model and be ready
4. Run single prompt test
5. Run batch of 15 prompts
6. Verify traces are being captured and uploaded

### 4. View Results

```bash
# Check deployment status
./deploy.sh status

# View logs
./deploy.sh logs

# Verify traces
./deploy.sh verify

# Download traces from S3
aws s3 sync s3://littleboy-research-traces/k3s-vllm/ ./traces/
```

## Manual Deployment

### Step-by-Step

```bash
# 1. Build eBPF sidecar image
./deploy.sh build

# 2. Deploy to K3s
./deploy.sh deploy

# 3. Wait for pod to be ready (5-10 minutes for model download)
kubectl get pods -n vllm-tracing -w

# 4. Run tests
./deploy.sh test

# 5. Verify traces
./deploy.sh verify
```

### Custom Configuration

Set environment variables before deployment:

```bash
# S3 bucket and prefix
export S3_BUCKET=my-traces-bucket
export S3_PREFIX=my-experiment/

# Deploy with custom settings
./deploy.sh deploy
```

## Testing

### Single Prompt Test

```bash
python3 test/single-prompt.py --host localhost --port 30800
```

Tests basic inference with one prompt. Results saved to `single_prompt_result_*.json`.

### Batch Prompts Test

```bash
# Sequential (default)
python3 test/batch-prompts.py --host localhost --port 30800 --count 15

# Parallel (4 concurrent requests)
python3 test/batch-prompts.py --host localhost --port 30800 --count 20 --parallel --workers 4
```

Tests throughput with multiple prompts. Results saved to `batch_prompts_result_*.json`.

### Verify Traces

```bash
./test/verify-traces.sh
```

Checks:
- eBPF sidecar is running
- vLLM process discovered
- Trace files being created
- S3 uploads working

## Trace Format

Traces are captured in JSONL format (one JSON object per line):

```json
{"ts":1234.567,"pid":12345,"type":"cuda_api","func":"cuInit","phase":"entry"}
{"ts":1234.890,"pid":12345,"type":"cuda_api","func":"cuDeviceGet","phase":"entry"}
{"ts":1235.123,"pid":12345,"type":"cuda_runtime","func":"cudaMalloc","phase":"entry"}
{"ts":1235.456,"pid":12345,"type":"cuda_api","func":"cuMemAlloc","phase":"entry"}
{"ts":1236.789,"pid":12345,"type":"cuda_api","func":"cuLaunchKernel","phase":"entry"}
```

Fields:
- `ts`: Timestamp in milliseconds from trace start
- `pid`: Process ID
- `type`: `cuda_api` (Driver API) or `cuda_runtime` (Runtime API)
- `func`: Function name (cuInit, cudaMalloc, etc.)
- `phase`: `entry` (function called)

## Analysis

### Download Traces

```bash
aws s3 sync s3://littleboy-research-traces/k3s-vllm/ ./traces/
```

### View Traces

```bash
# Count events
wc -l traces/*.jsonl

# View CUDA functions called
jq -r .func traces/trace_*.jsonl | sort | uniq -c | sort -rn

# Timeline of first 100 calls
head -100 traces/trace_*.jsonl | jq -r '[.ts, .func] | @tsv'

# Memory operations
grep -E "Mem|Alloc" traces/trace_*.jsonl | jq .

# Kernel launches
grep Launch traces/trace_*.jsonl | jq .
```

### Analysis Scripts

Coming soon:
- Token latency correlation
- Memory allocation patterns
- Kernel launch frequency
- Pipeline visualization

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n vllm-tracing -l app=vllm

# Common issues:
# 1. GPU not detected - check NVIDIA device plugin
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'

# 2. Image pull error - re-import to K3s
./deploy.sh build

# 3. Insufficient memory - check node resources
kubectl describe node
```

### eBPF Tracer Not Attaching

```bash
# Check tracer logs
kubectl logs -n vllm-tracing -l app=vllm -c ebpf-tracer

# Common issues:
# 1. vLLM not found - check process is running
kubectl exec -n vllm-tracing -it POD_NAME -c ebpf-tracer -- ps aux | grep vllm

# 2. Permission denied - check pod is privileged
kubectl get pod POD_NAME -n vllm-tracing -o yaml | grep privileged

# 3. CUDA libs not loaded - wait for vLLM to initialize
kubectl logs -n vllm-tracing -l app=vllm -c vllm | grep "Loading model"
```

### S3 Upload Failing

```bash
# Check AWS credentials
kubectl exec -n vllm-tracing -it POD_NAME -c ebpf-tracer -- aws s3 ls

# Check tracer logs for upload errors
kubectl logs -n vllm-tracing -l app=vllm -c ebpf-tracer | grep -i s3

# Test upload manually
kubectl exec -n vllm-tracing -it POD_NAME -c ebpf-tracer -- \
  aws s3 cp /traces/trace_*.jsonl s3://YOUR_BUCKET/test/
```

### vLLM API Not Responding

```bash
# Check if vLLM is ready
kubectl get pods -n vllm-tracing

# Check vLLM logs
kubectl logs -n vllm-tracing -l app=vllm -c vllm | tail -50

# Test health endpoint
curl http://localhost:30800/health

# Check service
kubectl get svc -n vllm-tracing
```

## Cleanup

```bash
# Delete all resources
./deploy.sh destroy

# Uninstall K3s (if needed)
sudo /usr/local/bin/k3s-uninstall.sh

# Remove Docker images
docker rmi littleboy/ebpf-cuda-tracer:latest
```

## Configuration Reference

### eBPF Sidecar Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_PROCESS` | `python` | Process name to trace |
| `S3_BUCKET` | - | S3 bucket for uploads (required) |
| `S3_PREFIX` | `k3s-vllm/` | S3 key prefix |
| `TRACE_INTERVAL` | `60` | Seconds between trace rotations |
| `TRACE_DIR` | `/traces` | Directory for trace files |
| `UPLOAD_ENABLED` | `true` | Enable S3 upload |

### vLLM Configuration

Edit `kubernetes/03-vllm-deployment.yaml`:

```yaml
# Model selection
--model meta-llama/Llama-2-7b-hf

# GPU memory utilization (0.0-1.0)
--gpu-memory-utilization 0.9

# Max sequence length
--max-model-len 2048

# Data type (float16, float32, bfloat16)
--dtype float16
```

## Performance Considerations

### eBPF Overhead

- **CPU**: <2% overhead on vLLM container
- **Memory**: ~500MB for tracer sidecar
- **Latency**: <0.1ms per CUDA call traced

### Resource Requests

Default requests in deployment:
- **vLLM**: 1 GPU, 12Gi RAM, 4 CPU
- **Tracer**: 0 GPU, 512Mi RAM, 0.5 CPU

Adjust based on your workload in `kubernetes/03-vllm-deployment.yaml`.

## Security Considerations

- **Privileged Container**: eBPF sidecar runs privileged (required for eBPF)
- **Host PID Namespace**: Required for cross-container process attachment
- **Secrets**: Store HF token and AWS credentials in Kubernetes secrets
- **RBAC**: Service account has minimal required permissions

## Project Structure

```
k3s-vllm-tracing/
├── deploy.sh                      # Main deployment script
├── README.md                      # This file
│
├── infrastructure/
│   └── k3s-install.sh            # K3s + GPU setup
│
├── docker/
│   └── ebpf-sidecar/
│       ├── Dockerfile            # Sidecar container image
│       ├── trace-and-upload.sh   # Main tracing script
│       └── requirements.txt      # Python dependencies
│
├── kubernetes/
│   ├── 00-namespace.yaml         # vllm-tracing namespace
│   ├── 01-storage.yaml           # PVC and ConfigMap
│   ├── 02-serviceaccount.yaml    # RBAC
│   ├── 03-vllm-deployment.yaml   # vLLM + sidecar deployment
│   └── 04-service.yaml           # NodePort service
│
└── test/
    ├── single-prompt.py          # Single inference test
    ├── batch-prompts.py          # Batch inference test
    └── verify-traces.sh          # Trace verification
```

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [K3s Documentation](https://docs.k3s.io/)
- [eBPF Documentation](https://ebpf.io/)
- [bpftrace Reference](https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)

## License

Part of the Little Boy GPU Research Project.

## Contributing

This is a research project. For issues or improvements, please document findings in the project research directory.
