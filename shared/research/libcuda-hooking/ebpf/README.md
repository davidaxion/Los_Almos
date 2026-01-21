# eBPF-Based CUDA Tracing

Complete eBPF solution for tracing CUDA applications from userspace API through kernel driver to GPU hardware.

## 🎯 Why eBPF?

**Flexibility for Future Extension:**
- ✅ Hook userspace (libcuda.so) automatically - no hardcoded function list
- ✅ Hook kernel space (nvidia.ko) - see driver internals
- ✅ Add new hooks without recompiling - just edit script
- ✅ Safe - kernel verifies eBPF programs
- ✅ Low overhead - runs in kernel VM
- ✅ Production ready - used by major companies

**Perfect for Little Boy Research:**
- See complete pipeline: CUDA API → IOCTL → GPU Scheduler
- Find context switch points
- Measure overhead at each layer
- Identify virtualization opportunities

## 🚀 Quick Start

### One-Command Tracing

```bash
# Simple trace (userspace only)
sudo ./run_trace.sh python your_inference.py

# With kernel hooks (full stack)
sudo ./run_trace.sh --kernel python your_inference.py

# Use BCC for more control
sudo ./run_trace.sh --method=bcc --kernel python your_inference.py
```

Output automatically saved to `traces/trace_<timestamp>.jsonl`

## 📁 Files

```
ebpf/
├── README.md                 # This file
├── KERNEL_HOOKS.md          # Guide to adding kernel-level hooks
│
├── trace_cuda_full.bt       # bpftrace script (userspace + kernel)
├── cuda_tracer.py           # BCC Python script (advanced)
├── run_trace.sh             # Runner script (simplifies usage)
│
└── traces/                  # Output directory (created automatically)
```

## 📊 What You Get

### Complete Pipeline Visibility

```
USERSPACE:
  cuInit → cuDeviceGet → cuCtxCreate → cuMemAlloc
    ↓ ioctl()
KERNEL:
  nvidia_ioctl → nv_mem_alloc → nv_schedule_work
    ↓
GPU:
  Executes work
```

### JSON Output

```jsonl
{"event_id":1,"ts":0.001,"type":"userspace","name":"cuInit","phase":"B"}
{"event_id":2,"ts":0.003,"type":"kernel","name":"nvidia_ioctl","phase":"B"}
{"event_id":3,"ts":0.004,"type":"scheduler","name":"nv_schedule_work"}
{"event_id":4,"ts":0.005,"type":"kernel","name":"nvidia_ioctl","phase":"E"}
{"event_id":5,"ts":0.006,"type":"userspace","name":"cuInit","phase":"E"}
```

### Real-Time Statistics

```
=== TRACE SUMMARY ===

USERSPACE (libcuda.so):
  Total CUDA API calls: 847
  Kernel launches: 42
  Memory allocations: 15
  Total memory allocated: 524288000 bytes (500.00 MB)
  Memory transfers: 128
  Total data transferred: 1048576000 bytes (1000.00 MB)

KERNEL SPACE (nvidia.ko):
  IOCTL calls: 1024
  Total IOCTL time: 15.234 ms
  Scheduler calls: 256
```

## 🛠️ Two Methods

### Method 1: bpftrace (Recommended)

**Pros:**
- Simple, high-level
- No programming required
- Quick to modify

**Usage:**
```bash
sudo ./run_trace.sh python inference.py
```

**Script:** `trace_cuda_full.bt`

### Method 2: BCC (Advanced)

**Pros:**
- Full Python control
- Better data structures
- Real-time analysis
- Dynamic function discovery

**Usage:**
```bash
sudo ./run_trace.sh --method=bcc --kernel python inference.py
```

**Script:** `cuda_tracer.py`

## 📚 How It Works

### bpftrace: Wildcard Matching

```c
// Automatically hooks ALL functions matching "cu*"
uprobe:/lib/*/libcuda.so:cu* {
    // This matches: cuInit, cuMemAlloc, cuLaunchKernel, ...
    // No need to list them explicitly!
}
```

### Kernel Hooks

```c
// Hook NVIDIA driver IOCTL handler
kprobe:nvidia_ioctl {
    // Runs when userspace calls ioctl() on /dev/nvidia*
}

// Hook GPU scheduler
kprobe:nv_schedule_work {
    // Runs when driver schedules work to GPU
}
```

### Complete Flow

```
1. Your app calls cuLaunchKernel()
   ↓
2. eBPF uprobe fires → logs function entry
   ↓
3. libcuda.so makes ioctl() syscall
   ↓
4. eBPF kprobe fires → logs kernel entry
   ↓
5. nvidia.ko schedules work to GPU
   ↓
6. eBPF kprobe fires → logs scheduler call
   ↓
7. Work executes on GPU
   ↓
8. Return path: all probes fire again for exits
```

## 🔧 Installation

### Ubuntu/Debian

```bash
# For bpftrace
sudo apt install bpftrace

# For BCC (optional, more advanced)
sudo apt install python3-bpfcc

# Verify installation
sudo bpftrace --version
python3 -c "import bcc; print('BCC installed')"
```

### Finding NVIDIA Functions

```bash
# List all hookable NVIDIA kernel functions
sudo bpftrace -l 'kprobe:nv*' | head -20
sudo bpftrace -l 'kprobe:nvidia*' | head -20

# Search for specific patterns
sudo bpftrace -l 'kprobe:*nvidia*ioctl*'
sudo bpftrace -l 'kprobe:*nv*mem*'
sudo bpftrace -l 'kprobe:*nv*sched*'
```

## 📖 Examples

### Example 1: Trace PyTorch Inference

```bash
# Create simple inference script
cat > inference.py << 'EOF'
import torch
model = torch.nn.Linear(1024, 1024).cuda()
x = torch.randn(32, 1024).cuda()
y = model(x)
print("Done!")
EOF

# Trace it
sudo ./run_trace.sh python inference.py

# View results
cat traces/trace_*.jsonl | head -20
```

### Example 2: Trace Specific Process

```bash
# Start your app in background
python long_running_inference.py &
PID=$!

# Attach tracer to specific PID
sudo bpftrace trace_cuda_full.bt -p $PID
```

### Example 3: Real-Time Monitoring

```bash
# Show live events as they happen
sudo bpftrace trace_cuda_full.bt | grep -E 'cuLaunchKernel|nvidia_ioctl'
```

### Example 4: Focus on Memory Operations

```bash
# Modify script to only trace memory operations
sudo bpftrace -e '
  uprobe:/lib/*/libcuda.so:cuMem* {
    printf("%s\n", probe);
  }
'
```

## 🎓 Adding Custom Hooks

See **[KERNEL_HOOKS.md](KERNEL_HOOKS.md)** for detailed guide on:
- Finding kernel functions to hook
- Decoding IOCTL commands
- Tracking GPU scheduler calls
- Measuring context switch overhead
- Correlating userspace and kernel events

Quick example:

```bash
# 1. Find functions
sudo bpftrace -l 'kprobe:*nv*sched*'

# 2. Test hook
sudo bpftrace -e 'kprobe:nv_schedule_work { printf("Scheduled!\n"); }'

# 3. Add to trace_cuda_full.bt
# Edit line ~250 and add your hook
```

## 📊 Analyzing Results

### With visualize_pipeline.py

```bash
# Generate ASCII timeline
python ../tools/visualize_pipeline.py traces/trace_latest.jsonl

# Generate Chrome trace
python ../tools/visualize_pipeline.py --format=chrome traces/trace_latest.jsonl
# Open trace.json in chrome://tracing
```

### Manual Analysis

```bash
# Count events by type
jq -r '.type' traces/trace_*.jsonl | sort | uniq -c

# Find slowest operations
jq 'select(.duration_us) | {name, duration_us}' traces/trace_*.jsonl | \
    jq -s 'sort_by(.duration_us) | reverse | .[0:10]'

# Memory allocation summary
jq 'select(.type=="memory")' traces/trace_*.jsonl | \
    jq -s 'map(.size) | add'
```

## 🔬 For Little Boy Research

### Finding Context Switch Points

```bash
# Look for context-related kernel calls
sudo bpftrace -l 'kprobe:*nv*ctx*'

# Trace them
sudo bpftrace -e '
  kprobe:nv_create_context,
  kprobe:nv_destroy_context,
  kprobe:nv_bind_context* {
    printf("[%lld] %s\n", nsecs, probe);
  }
'
```

### Measuring Scheduler Overhead

```bash
# Time spent in scheduler
sudo bpftrace -e '
  kprobe:nv_schedule_work { @start[tid] = nsecs; }
  kretprobe:nv_schedule_work {
    @scheduler_time_us = hist((nsecs - @start[tid]) / 1000);
  }
'
```

### Finding Idle Periods

```bash
# Gap between kernel launches = idle GPU time
jq 'select(.type=="kernel" and .name=="cuLaunchKernel")' trace.jsonl | \
    jq -s 'map(.ts) | . as $times |
           range(length-1) |
           {gap: ($times[.+1] - $times[.])}' | \
    jq -s 'map(.gap) | add / length'
```

## 🐛 Troubleshooting

### Permission Denied

```bash
# Must run as root
sudo ./run_trace.sh python test.py
```

### bpftrace Not Found

```bash
sudo apt update
sudo apt install bpftrace
```

### No Kernel Hooks Firing

```bash
# Check if NVIDIA module is loaded
lsmod | grep nvidia

# List available hooks
sudo bpftrace -l 'kprobe:nvidia*' | wc -l

# If zero, driver might be using different names
# Try: nv*, gpu*, or check dmesg for module name
```

### Too Many Events

```bash
# Limit to specific functions
sudo bpftrace -e '
  uprobe:/lib/*/libcuda.so:cuLaunchKernel,
  uprobe:/lib/*/libcuda.so:cuMemAlloc {
    printf("%s\n", probe);
  }
'
```

### BCC Import Error

```bash
# Install BCC Python bindings
sudo apt install python3-bpfcc

# Or use pip (not recommended)
pip3 install bcc
```

## 🔐 Security Note

eBPF programs are **kernel-verified** before loading:
- Can't crash the kernel
- Can't access arbitrary memory
- Can't infinite loop
- Resource limits enforced

Safe to use even on production systems (with performance considerations).

## 📈 Performance Impact

### bpftrace Overhead

```
Fast operations (< 10 μs):  +5-10 μs per call
Slow operations (> 1 ms):   < 1% overhead
GPU operations (> 10 ms):   < 0.1% overhead
```

### BCC Overhead

Similar to bpftrace, slightly lower due to optimizations.

### Recommendation

- Development/research: Use all hooks
- Production: Hook only critical path
- Benchmarking: Disable or use sampling

## 🎯 Next Steps

1. **Run basic trace:**
   ```bash
   sudo ./run_trace.sh python -c "import torch; torch.cuda.init()"
   ```

2. **Analyze results:**
   ```bash
   cat traces/trace_*.jsonl | jq -r '.name' | sort | uniq -c
   ```

3. **Add kernel hooks:**
   - Read [KERNEL_HOOKS.md](KERNEL_HOOKS.md)
   - Find functions: `sudo bpftrace -l 'kprobe:nv*'`
   - Edit `trace_cuda_full.bt`

4. **Trace your workloads:**
   ```bash
   sudo ./run_trace.sh --kernel python your_inference.py
   ```

5. **Design Little Boy hooks based on findings**

## 📚 Further Reading

- [bpftrace Reference Guide](https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md)
- [BCC Python Developer Tutorial](https://github.com/iovisor/bcc/blob/master/docs/tutorial_bcc_python_developer.md)
- [eBPF.io](https://ebpf.io/) - Official eBPF site
- **KERNEL_HOOKS.md** - Our guide to kernel-level tracing
- **../notes/tracing-mechanics.md** - Deep dive into how hooks work
