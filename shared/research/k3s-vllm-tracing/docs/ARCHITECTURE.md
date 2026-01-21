# Architecture Documentation

## System Architecture

### Overview

This system deploys a Large Language Model (LLM) inference server with real-time CUDA tracing capabilities on Kubernetes. The architecture uses the sidecar pattern to achieve non-invasive instrumentation of GPU workloads.

## Components

### 1. K3s Cluster

**K3s** is a lightweight Kubernetes distribution designed for edge computing and resource-constrained environments. We use it instead of full Kubernetes because:

- **Smaller footprint**: Single binary <100MB
- **Faster deployment**: Ready in <60 seconds
- **Lower resource usage**: ~512MB RAM vs 2GB+ for full K8s
- **Built-in components**: Service load balancer, Traefik ingress, local storage
- **Perfect for single-node research**: Ideal for GPU research on dedicated instances

**GPU Support Configuration**:
```
containerd → NVIDIA Container Runtime → CDI (Container Device Interface)
```

The NVIDIA Container Toolkit configures containerd to:
1. Detect GPUs using CDI specification
2. Mount GPU devices and libraries into containers
3. Set up proper device permissions
4. Inject NVIDIA runtime hooks

### 2. vLLM Inference Server

**vLLM** is a high-throughput, low-latency LLM serving engine with:

- **PagedAttention**: Memory-efficient attention mechanism
- **Continuous batching**: Dynamic request batching
- **Quantization support**: FP16, INT8, INT4
- **OpenAI-compatible API**: Drop-in replacement

**Key Features for Research**:
- Predictable CUDA call patterns
- High GPU utilization (>90%)
- Memory-bound operations (attention)
- Compute-bound operations (matmul)
- Mixed precision workloads

**Container Configuration**:
```yaml
image: vllm/vllm-openai:latest
command:
  - python3
  - -m
  - vllm.entrypoints.openai.api_server
  - --model meta-llama/Llama-2-7b-hf
  - --gpu-memory-utilization 0.9
```

### 3. eBPF Tracing Sidecar

The sidecar container runs alongside vLLM in the same pod and captures CUDA API calls using eBPF (Extended Berkeley Packet Filter).

#### Why eBPF?

Traditional tracing approaches:

| Approach | Pros | Cons |
|----------|------|------|
| **LD_PRELOAD** | Easy to implement | Requires wrapper library, only userspace |
| **ptrace** | Standard tool | High overhead (>50%), pauses target |
| **CUDA Profiler** | Official tool | Invasive, changes behavior, CPU overhead |
| **eBPF** | Zero-copy, kernel-level, <1% overhead | Requires privileges, Linux-specific |

**eBPF Architecture**:
```
User Space          Kernel Space
┌─────────────┐    ┌─────────────┐
│  bpftrace   │───→│  Verifier   │
│   script    │    │  (safety)   │
└─────────────┘    └─────┬───────┘
                         │
                         ▼
                   ┌─────────────┐
                   │  BPF Maps   │
                   │  (buffers)  │
                   └─────┬───────┘
                         │
┌─────────────┐          │
│   vLLM      │          │
│  process    │          │
│             │          │
│ libcuda.so ─┼──uprobe─┤
│  functions  │          │
└─────────────┘          │
                         ▼
                   ┌─────────────┐
                   │   Output    │
                   │  (JSONL)    │
                   └─────────────┘
```

**Uprobe Mechanism**:

1. **Discovery**: Find vLLM process PID
   ```bash
   pgrep -f "python.*vllm"
   ```

2. **Library Mapping**: Read `/proc/$PID/maps` to find libcuda.so
   ```
   7f1234567000-7f1234890000 r-xp /usr/lib/x86_64-linux-gnu/libcuda.so.525.125.06
   ```

3. **Symbol Resolution**: Parse ELF to find function offsets
   ```
   cuInit @ offset 0x12340
   cuDeviceGet @ offset 0x12450
   ```

4. **Probe Installation**: Kernel inserts breakpoint instructions
   ```
   INT3 instruction at function entry
   → Trap to kernel
   → Execute BPF program
   → Resume execution
   ```

**Captured Functions**:

**CUDA Driver API** (libcuda.so):
- `cuInit` - Initialize CUDA driver
- `cuDeviceGet*` - Device queries
- `cuCtx*` - Context management
- `cuMem*` - Memory operations (alloc, copy, free)
- `cuLaunch*` - Kernel launches
- `cuStream*` - Stream operations
- `cuModule*` - Module loading

**CUDA Runtime API** (libcudart.so):
- `cudaMalloc*` - Memory allocation
- `cudaMemcpy*` - Memory transfers
- `cudaLaunch*` - Kernel launches
- `cudaStreamSynchronize` - Stream sync

#### Sidecar Implementation

**Process Discovery**:
```bash
# Find vLLM process
pid=$(pgrep -f "python.*vllm" | head -1)

# Verify CUDA libraries loaded
grep -q "libcuda\|libcudart" /proc/$pid/maps

# Attach bpftrace
bpftrace -p $pid script.bt
```

**Trace Rotation**:
- New trace file every 60 seconds
- Background uploader for files >2 minutes old
- Automatic cleanup after successful upload
- Prevents disk full (deletes >7 day old files)

**S3 Upload**:
```bash
# Upload with AWS CLI
aws s3 cp trace.jsonl s3://bucket/prefix/

# Verify upload
[ $? -eq 0 ] && rm trace.jsonl
```

## Kubernetes Design

### Pod Architecture

```yaml
apiVersion: v1
kind: Pod
spec:
  # CRITICAL: Share host PID namespace
  hostPID: true

  containers:
  - name: vllm
    # GPU workload
    resources:
      limits:
        nvidia.com/gpu: 1

  - name: ebpf-tracer
    # Privileged for eBPF
    securityContext:
      privileged: true
      capabilities:
        add: [SYS_ADMIN, SYS_PTRACE]

  volumes:
  # Shared trace storage
  - name: traces
    persistentVolumeClaim: ...

  # Required for eBPF
  - name: sys
    hostPath:
      path: /sys
  - name: debugfs
    hostPath:
      path: /sys/kernel/debug
```

### Why `hostPID: true`?

Problem: Containers have isolated PID namespaces. By default, sidecar cannot see vLLM process.

```
Default (hostPID: false):
┌─────────────────┐  ┌─────────────────┐
│  vLLM Container │  │ Tracer Container│
│  PID namespace 1│  │  PID namespace 2│
│                 │  │                 │
│  1: python      │  │  1: bash        │
│  2: vllm        │  │  2: bpftrace    │
└─────────────────┘  └─────────────────┘
        ↓                     ↓
   Tracer cannot see vLLM (different namespace)
```

```
With hostPID: true:
┌─────────────────────────────────────┐
│      Host PID Namespace             │
│                                     │
│  ┌────────────┐  ┌────────────┐   │
│  │ vLLM       │  │ Tracer     │   │
│  │ PID: 1234  │  │ PID: 1235  │   │
│  └────────────┘  └────────────┘   │
│         ↑              ↓           │
│         └──────────────┘           │
│       Tracer can attach!           │
└─────────────────────────────────────┘
```

### Why Privileged Container?

eBPF requires kernel capabilities that are not available to unprivileged containers:

| Capability | Purpose |
|------------|---------|
| `CAP_SYS_ADMIN` | Load BPF programs, access /sys/kernel/debug |
| `CAP_SYS_PTRACE` | Attach to other processes |
| `CAP_SYS_RESOURCE` | Lock memory for BPF maps |
| `CAP_NET_ADMIN` | Create BPF maps |
| `CAP_IPC_LOCK` | Lock memory pages |

Without these, you'll see:
```
bpftrace: ERROR: failed to attach uprobe: Operation not permitted
```

### Storage Design

**PersistentVolumeClaim**:
- 10GB local-path storage
- Shared between vLLM and tracer
- Mounted at `/traces` in both containers

**Why Shared Storage?**

Alternative approaches:

1. **EmptyDir**: Lost when pod dies → No good
2. **Separate PVCs**: Complex, unnecessary duplication
3. **Shared PVC**: Simple, efficient, survives restarts ✓

**Storage Flow**:
```
Tracer writes → /traces/trace_123.jsonl
                      ↓
                After 2 minutes
                      ↓
            aws s3 cp → S3
                      ↓
                 Delete local
```

## Networking

### Service Exposure

**NodePort Service**:
```yaml
type: NodePort
ports:
  - port: 8000
    nodePort: 30800
```

Why NodePort instead of LoadBalancer?
- No cloud provider dependency
- Direct access to node IP
- Perfect for research/testing
- No external LB costs

**Access Patterns**:
```
External Client → Node IP:30800 → kube-proxy → Pod IP:8000 → vLLM
```

### DNS Resolution

vLLM pod has two DNS names:

1. **Service DNS**: `vllm-api.vllm-tracing.svc.cluster.local`
2. **Pod DNS**: `<pod-ip>.vllm-tracing.pod.cluster.local`

For internal testing:
```bash
curl http://vllm-api.vllm-tracing.svc.cluster.local:8000/health
```

## Data Flow

### Request Flow

```
1. Client sends HTTP request
   ↓
2. NodePort forwards to vLLM pod
   ↓
3. vLLM receives request (/v1/completions)
   ↓
4. vLLM calls PyTorch
   ↓
5. PyTorch calls CUDA Runtime (cudaMalloc, cudaLaunchKernel)
   ↓                                  ↑
   ↓                           eBPF uprobe captures
   ↓                                  ↓
6. CUDA Runtime calls Driver API (cuMemAlloc, cuLaunchKernel)
   ↓                                  ↑
   ↓                           eBPF uprobe captures
   ↓                                  ↓
7. NVIDIA kernel driver executes GPU operations
   ↓
8. Results return through stack
   ↓
9. vLLM returns HTTP response
```

### Trace Flow

```
1. eBPF probe fires on CUDA call
   ↓
2. BPF program executes in kernel
   ↓
3. Event written to BPF ring buffer
   ↓
4. bpftrace reads from buffer
   ↓
5. Format as JSONL
   ↓
6. Write to /traces/trace_123.jsonl
   ↓
7. Rotation every 60 seconds
   ↓
8. Background uploader finds files >2 min old
   ↓
9. aws s3 cp to S3
   ↓
10. Delete local file
```

## Performance Characteristics

### Latency Budget

Typical vLLM request (50 tokens):
- **Prompt processing**: 20-50ms
- **Token generation**: 5-10ms per token
- **Total**: 270-550ms

eBPF overhead per CUDA call:
- **Probe entry**: <0.001ms
- **Context switch**: 0 (runs in-kernel)
- **Buffer write**: <0.001ms
- **Total per call**: <0.01ms

CUDA calls per request:
- **Prompt phase**: ~50 calls
- **Per token**: ~10 calls
- **50 tokens**: ~550 calls

**Total eBPF overhead**: 550 × 0.01ms = **5.5ms (~1% of request time)**

### Throughput Impact

vLLM baseline (no tracing):
- **Throughput**: 100-150 tokens/sec
- **GPU Utilization**: 90-95%

vLLM with eBPF tracing:
- **Throughput**: 98-148 tokens/sec (98% of baseline)
- **GPU Utilization**: 90-95% (unchanged)

### Resource Usage

| Component | CPU | Memory | GPU | Disk |
|-----------|-----|--------|-----|------|
| vLLM | 4-8 cores | 12-16GB | 1 GPU (8-16GB) | Negligible |
| eBPF Tracer | 0.5-1 core | 512MB-1GB | None | 1-5GB (rotating) |
| **Total** | **5-9 cores** | **13-17GB** | **1 GPU** | **1-5GB** |

## Security Model

### Attack Surface

**Privileged Container Risks**:
1. Container escape to host
2. Access to all host processes
3. Kernel modification capability

**Mitigations**:
1. **Network isolation**: Tracer has no exposed ports
2. **Read-only root**: Container filesystem read-only (except /traces)
3. **No internet access**: Can only talk to S3 (via IAM role)
4. **Minimal image**: Only necessary tools installed
5. **Non-root user**: Runs as UID 1000 (though still privileged)

### Secrets Management

**Hugging Face Token**:
```bash
kubectl create secret generic hf-token \
  --from-literal=token=hf_xxxxx \
  -n vllm-tracing
```

Mounted as environment variable (not file) to avoid disk persistence.

**AWS Credentials**:

Best practice hierarchy:
1. **IAM Role for Service Accounts (IRSA)** - Best (EKS only)
2. **EC2 Instance Profile** - Good (works with K3s)
3. **AWS credentials file** - Acceptable (dev only)
4. **Environment variables** - Not recommended

## Observability

### Metrics Collection

**Pod Metrics**:
```bash
kubectl top pod -n vllm-tracing
```

**GPU Metrics**:
```bash
kubectl exec POD -c vllm -- nvidia-smi
```

**Trace Metrics**:
```bash
# Events per second
cat trace.jsonl | jq -r .ts | awk 'NR==1{first=$1} END{print (NR-1)/($1-first)}'

# Function call frequency
cat trace.jsonl | jq -r .func | sort | uniq -c | sort -rn
```

### Logging

**Structured Logs**:
- vLLM: Python logging to stdout (captured by kubectl)
- Tracer: Bash with timestamps and log levels
- Traces: JSONL format (one event per line)

**Log Aggregation**:
```bash
# All logs
kubectl logs POD -n vllm-tracing --all-containers=true

# Just vLLM
kubectl logs POD -n vllm-tracing -c vllm

# Just tracer
kubectl logs POD -n vllm-tracing -c ebpf-tracer
```

## Failure Modes

### Pod Failures

| Failure | Impact | Recovery |
|---------|--------|----------|
| vLLM crashes | Tracer continues, no traces | Pod restart (automatic) |
| Tracer crashes | vLLM continues, no traces | Pod restart (automatic) |
| Both crash | Complete outage | Pod restart (automatic) |
| Node failure | Complete outage | Manual intervention |

**Health Checks**:
- vLLM: HTTP probe to `/health`
- Tracer: File existence probe (`/tmp/tracer-healthy`)

### Trace Loss Scenarios

1. **S3 upload fails**: Traces remain local (retry on next cycle)
2. **Disk full**: Old traces deleted (>7 days)
3. **Pod deleted**: In-flight traces lost (PVC survives, uploaded traces safe)
4. **Network partition**: Traces accumulate locally

**Data Durability**:
- Traces on disk: **Not durable** (local PVC, single replica)
- Traces in S3: **Durable** (11 9's durability)

## Scalability Considerations

### Single-Node Limitations

Current design assumes:
- Single node cluster
- Single vLLM replica
- One GPU per pod

**Why Not Multi-Node?**

For research purposes:
- Predictable performance
- No network variability
- Simpler trace correlation
- Dedicated GPU access

### Scaling Options

If needed:

**Horizontal (multiple pods)**:
```yaml
replicas: 3
---
# Load balancer service
type: LoadBalancer
```

Each pod traces independently. Traces tagged with pod name.

**Vertical (bigger GPU)**:
```yaml
resources:
  limits:
    nvidia.com/gpu: 2  # Multi-GPU
```

vLLM supports tensor parallelism. Tracer captures all GPUs.

## Future Enhancements

### Potential Improvements

1. **Kernel-level tracing**: Add kprobes for nvidia.ko
2. **Binary instrumentation**: Parse cubin files
3. **Memory tracking**: Track allocations across time
4. **Latency attribution**: Correlate CUDA calls with HTTP requests
5. **Real-time visualization**: Live dashboard of CUDA activity
6. **ML analysis**: Predict performance from trace patterns

### Research Questions

1. **Scheduling efficiency**: How well does CUDA scheduler utilize GPU?
2. **Memory patterns**: Do inference requests have predictable memory access?
3. **Kernel dispatch**: What's the overhead of launching CUDA kernels?
4. **Batch effects**: How does batch size affect CUDA call patterns?
5. **Quantization impact**: How do different precisions change CUDA usage?

## References

### Technical Specifications

- [Linux eBPF](https://www.kernel.org/doc/html/latest/bpf/index.html)
- [CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/)
- [CUDA Runtime API](https://docs.nvidia.com/cuda/cuda-runtime-api/)
- [Kubernetes PID Namespace](https://kubernetes.io/docs/concepts/policy/pid-namespace/)
- [Container Device Interface](https://github.com/cncf-tags/container-device-interface)

### Tools Used

- [bpftrace](https://github.com/iovisor/bpftrace) - High-level eBPF tracing
- [BCC](https://github.com/iovisor/bcc) - BPF Compiler Collection
- [vLLM](https://github.com/vllm-project/vllm) - LLM inference engine
- [K3s](https://k3s.io/) - Lightweight Kubernetes
