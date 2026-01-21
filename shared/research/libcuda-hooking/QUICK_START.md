# Quick Start - CUDA API Hooking & Pipeline Visualization

## Overview

This toolkit provides **automatic hooking of ALL CUDA API calls** without hardcoding specific functions. It captures the complete execution pipeline from model loading through inference to results.

## How It Works

### The Magic: LD_PRELOAD

```
Your App → cuLaunchKernel()
              ↓
         [LD_PRELOAD intercepts]
              ↓
    libcuda_hook.so captures call
              ↓
         Calls real libcuda.so
              ↓
         Returns to your app
```

See `notes/how-hooking-works.md` for detailed explanation.

## Three Methods Available

### Method 1: LD_PRELOAD (Recommended - No Root Required)

Hooks CUDA functions by loading our library before libcuda.so

**Pros**: No root, works with any CUDA app, detailed timing
**Cons**: Only sees userspace API calls

### Method 2: eBPF/bpftrace (Generic - Best Coverage)

Uses kernel uprobes to hook ALL functions matching patterns automatically

**Pros**: Hooks everything automatically, no hardcoded functions
**Cons**: Requires root access

### Method 3: strace (System Call Level)

Traces ioctl() calls to the NVIDIA kernel driver

**Pros**: Shows kernel driver communication
**Cons**: Low-level, harder to interpret

## Quick Start

### 1. Simple Trace (LD_PRELOAD)

```bash
cd research/libcuda-hooking/tools
./trace_cuda.sh python your_inference.py
```

This will:
1. Build the hook library (first run only)
2. Run your app with hooks enabled
3. Generate `traces/trace_<timestamp>_ld_preload.jsonl`
4. Auto-generate visualization

### 2. Generic Trace (eBPF - Hooks Everything)

```bash
sudo ./trace_cuda.sh --method=ebpf python your_inference.py
```

This uses bpftrace to automatically hook ALL cu* functions without hardcoding!

### 3. All Methods Combined

```bash
sudo ./trace_cuda.sh --method=all python your_inference.py
```

Runs all three methods simultaneously.

## Example Output

### ASCII Timeline

```
=== CUDA EXECUTION PIPELINE - ASCII Timeline ===

Total execution time: 24.731 ms

Legend:
  ▓ = init
  █ = memory_mgmt
  ▒ = transfer
  ● = kernel
  ░ = sync

Depth 0:
  ▓█████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒●░░▒▒▒▒▒▒▒▒▒

Depth 1:
      ███  ▒▒▒▒▒▒   ▒▒▒▒▒      ●    ▒▒▒▒▒

Time scale (ms):
       0.0    2.5    5.0    7.5   10.0   12.5   15.0   17.5   20.0   22.5   25.0
```

### Pipeline Summary

```
PIPELINE SUMMARY - Operation Breakdown

Category             Count      Total Time        Avg Time   % of Total
----------------------------------------------------------------------------------------------------
init                     3        0.123 ms        0.041 ms         0.5%
memory_mgmt              2        0.356 ms        0.178 ms         1.4%
transfer                 3       13.789 ms        4.596 ms        55.8%
kernel                   1        5.234 ms        5.234 ms        21.2%
sync                     1        5.229 ms        5.229 ms        21.1%
----------------------------------------------------------------------------------------------------
TOTAL                   10       24.731 ms
```

### Top Operations

```
TOP 20 LONGEST OPERATIONS

#    Function                                 Duration        Category
----------------------------------------------------------------------------------------------------
1    cuMemcpyHtoD                                5.670 ms transfer
2    cuMemcpyHtoD                                5.234 ms transfer
3    cuStreamSynchronize                         5.229 ms sync
4    cuLaunchKernel                              0.123 ms kernel
5    cuMemcpyDtoH                                2.885 ms transfer
```

## Visualization Options

### 1. Chrome Trace Viewer

```bash
python visualize_pipeline.py --format=chrome trace.jsonl
# Open trace.json in chrome://tracing
```

Interactive timeline with zoom, search, and analysis tools.

### 2. Flamegraph

```bash
python visualize_pipeline.py --format=flamegraph trace.jsonl
flamegraph.pl flamegraph.txt > flamegraph.svg
```

Shows call hierarchy and time distribution.

### 3. ASCII (Terminal)

```bash
python visualize_pipeline.py --format=ascii trace.jsonl
```

Quick view in your terminal.

## Real-World Example

### Trace PyTorch Inference

```bash
# Create simple inference script
cat > inference.py << 'EOF'
import torch
import time

print("Loading model...")
model = torch.nn.Linear(1024, 1024).cuda()

print("Running inference...")
for i in range(10):
    x = torch.randn(32, 1024).cuda()
    y = model(x)
    print(f"Iteration {i+1} done")

print("Complete!")
EOF

# Trace it
./trace_cuda.sh python inference.py
```

### Output Shows

1. **Initialization**: cuInit, cuDeviceGet, cuCtxCreate (< 1ms)
2. **Model Loading**: cuMemAlloc for weights (varies by model size)
3. **Per Iteration**:
   - cuMemcpyHtoD: Transfer input (depends on batch size)
   - cuLaunchKernel: Matrix multiply
   - cuMemcpyDtoH: Transfer result back
4. **Synchronization**: Where GPU waits

### Insights You'll Get

```
Memory Transfers: 68.5% of time ← BOTTLENECK
Kernel Execution: 21.3% of time
Overhead:         10.2% of time

Optimization opportunities:
- Reduce H2D transfers (keep data on GPU)
- Batch multiple requests
- Use async streams to overlap transfers and compute
```

## Understanding Your Results

### Key Metrics

1. **Category Percentages**: Where time is spent
   - High transfer %? → Optimize data movement
   - High sync %? → Poor stream utilization
   - High kernel %? → Compute-bound (good!)

2. **Operation Count**:
   - Many small transfers? → Batch them
   - Frequent context switches? → Virtualization opportunity

3. **Timeline Gaps**:
   - GPU idle time shows scheduling opportunities
   - These are where Little Boy can multiplex workloads

### For Little Boy Research

The traces reveal:

- **Context switch points**: When GPU switches between tasks
- **Memory allocation patterns**: How to virtualize VRAM
- **Scheduling decisions**: Where driver makes GPU busy/idle choices
- **Overhead breakdown**: Cost of each API layer

## Next Steps

1. **Trace your baseline workloads**
   ```bash
   ./trace_cuda.sh python real_time_inference.py
   ./trace_cuda.sh python batch_processing.py
   ./trace_cuda.sh python training.py
   ```

2. **Compare traces** to find patterns

3. **Load binaries in Ghidra**
   - See `binaries/README.md`
   - Correlate API calls with driver IOCTLs

4. **Design Little Boy's interception points**
   - Based on context switches you observe
   - At memory allocation boundaries
   - During sync operations (idle time)

## Troubleshooting

### LD_PRELOAD hook not working

```bash
# Make sure library is built
cd hooks && make

# Check LD_PRELOAD is set
export CUDA_HOOK_TRACE=trace.jsonl
LD_PRELOAD=./libcuda_hook.so python -c "import torch; print(torch.cuda.is_available())"
```

### eBPF not attaching

```bash
# Check bpftrace is installed
sudo apt install bpftrace  # Ubuntu
brew install bpftrace      # macOS (limited support)

# Check libcuda.so location
find /usr /lib -name "libcuda.so*" 2>/dev/null

# Update paths in trace_all_cuda.bt if needed
```

### No trace output

```bash
# Check trace file location
ls -la traces/

# Check stderr for errors
./trace_cuda.sh python test.py 2>&1 | tee debug.log

# Verify CUDA is actually being used
python -c "import torch; print(torch.cuda.is_available())"
```

## Files Reference

```
research/libcuda-hooking/
├── hooks/
│   ├── cuda_hook.c              # Specific function hooks
│   ├── generic_cuda_hook.c      # Generic hooking (experimental)
│   └── Makefile                 # Build system
├── tools/
│   ├── trace_cuda.sh            # All-in-one tracer
│   ├── trace_all_cuda.bt        # eBPF generic hooking script
│   └── visualize_pipeline.py    # Visualization generator
├── binaries/
│   ├── libcuda.so               # For Ghidra analysis
│   └── nvidia-kernel.o          # For Ghidra analysis
└── notes/
    ├── how-hooking-works.md     # Detailed explanation
    ├── hooking-approach.md      # Strategy and implementation
    └── getting-started.md       # Initial setup guide
```

## Further Reading

- `notes/how-hooking-works.md` - Deep dive into LD_PRELOAD mechanism
- `notes/hooking-approach.md` - Complete strategy for inference flow tracing
- `binaries/README.md` - Guide to reverse engineering with Ghidra
