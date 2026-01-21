# CUDA API Hooking & Pipeline Visualization

Complete toolkit for tracing and visualizing CUDA execution from start to finish, showing the entire pipeline from model loading through inference to results.

## 📋 What This Does

**Automatically hooks ALL CUDA API calls** and generates a complete visual pipeline showing:
- ⏱️ Exact timing of every operation
- 📊 Time breakdown by category (memory, transfer, kernel, sync)
- 🔍 Bottleneck identification
- 📈 Call hierarchy and depth
- 🎯 GPU scheduling opportunities

## 🎯 Three Tracing Methods

### 1. LD_PRELOAD (Recommended)
- ✅ No root access required
- ✅ Low overhead (~2 μs per call)
- ✅ Detailed timing and parameters
- ⚠️ Requires building hook library

### 2. eBPF (Best for generic hooking)
- ✅ Automatically hooks ALL cu* functions
- ✅ No hardcoded function list
- ✅ Safe, kernel-verified
- ⚠️ Requires root/sudo

### 3. strace (System call level)
- ✅ Shows IOCTL communication with driver
- ✅ No library needed
- ⚠️ High overhead, low-level output

## 🚀 Quick Start

```bash
# Simple trace (no root needed)
cd tools
./trace_cuda.sh python your_inference.py

# Hook everything with eBPF (requires sudo)
sudo ./trace_cuda.sh --method=ebpf python your_inference.py

# All methods combined
sudo ./trace_cuda.sh --method=all python your_inference.py
```

This automatically:
1. Traces your CUDA application
2. Generates trace file (JSONL format)
3. Creates visualizations (ASCII, Chrome trace)
4. Shows statistics and bottlenecks

## 📖 Documentation

### Start Here
- **[QUICK_START.md](QUICK_START.md)** - Installation and usage guide
- **[notes/tracing-quick-reference.md](notes/tracing-quick-reference.md)** - Visual diagrams and cheat sheet

### Deep Dives
- **[notes/how-hooking-works.md](notes/how-hooking-works.md)** - LD_PRELOAD mechanism explained
- **[notes/tracing-mechanics.md](notes/tracing-mechanics.md)** - Complete technical deep-dive
- **[notes/hooking-approach.md](notes/hooking-approach.md)** - Strategy for inference flow tracing
- **[notes/getting-started.md](notes/getting-started.md)** - Initial setup and Ghidra analysis

## 🛠️ How It Works

### LD_PRELOAD Magic

```
LD_PRELOAD=./libcuda_hook.so python script.py

Linux loads libraries in this order:
  1. libcuda_hook.so (OUR HOOK) ← Loaded FIRST
  2. libcuda.so (REAL CUDA)

When your code calls cuLaunchKernel():
  → Goes to OUR function (symbol table points to hook)
  → We log timestamp, params
  → We call REAL cuLaunchKernel()
  → We log result, duration
  → Return to your code

Result: Every CUDA call is logged!
```

See `notes/tracing-quick-reference.md` for visual diagrams.

### eBPF Generic Hooking

```bash
# This automatically hooks ALL functions matching "cu*"
sudo bpftrace trace_all_cuda.bt

How it works:
  1. Kernel patches ALL cu* functions with breakpoints
  2. When function is called → CPU traps to kernel
  3. Kernel runs BPF program (logs the call)
  4. Executes original instruction
  5. Returns to userspace

No hardcoded function list needed!
```

## 📊 Example Output

### ASCII Timeline
```
=== CUDA EXECUTION PIPELINE ===

Total execution time: 24.731 ms

Legend: ▓=init █=memory ▒=transfer ●=kernel ░=sync

Depth 0:
  ▓█████▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒●░░▒▒▒▒▒▒▒▒▒
```

### Statistics
```
Category          Count   Total Time    % of Total
----------------------------------------------------
transfer              3    13.789 ms        55.8%  ← BOTTLENECK
kernel                1     5.234 ms        21.2%
sync                  1     5.229 ms        21.1%
memory_mgmt           2     0.356 ms         1.4%
init                  3     0.123 ms         0.5%
```

### Top Operations
```
#  Function              Duration     Category
------------------------------------------------
1  cuMemcpyHtoD          5.670 ms    transfer
2  cuMemcpyHtoD          5.234 ms    transfer
3  cuStreamSynchronize   5.229 ms    sync
4  cuLaunchKernel        0.123 ms    kernel
```

## 📁 Project Structure

```
research/libcuda-hooking/
├── README.md                    # This file
├── QUICK_START.md              # Getting started guide
│
├── hooks/                      # Hook implementations
│   ├── cuda_hook.c            # Specific function hooks
│   ├── generic_cuda_hook.c    # Generic hooking (experimental)
│   └── Makefile               # Build system
│
├── tools/                      # Tracing and visualization
│   ├── trace_cuda.sh          # All-in-one tracer script
│   ├── trace_all_cuda.bt      # eBPF generic hooking
│   └── visualize_pipeline.py  # Pipeline visualization
│
├── binaries/                   # For reverse engineering
│   ├── libcuda.so             # CUDA library (92MB)
│   ├── nvidia-kernel.o        # Kernel driver blob (107MB)
│   └── README.md              # Analysis guide
│
└── notes/                      # Documentation
    ├── how-hooking-works.md        # LD_PRELOAD explained
    ├── tracing-mechanics.md        # Deep technical dive
    ├── tracing-quick-reference.md  # Visual cheat sheet
    ├── hooking-approach.md         # Inference flow strategy
    └── getting-started.md          # Setup and Ghidra guide
```

## 🎓 Understanding Your Results

### Key Insights

**High transfer percentage?**
→ Data movement is the bottleneck
→ Keep data on GPU, batch transfers

**Many context switches?**
→ Poor GPU utilization
→ Virtualization opportunity for Little Boy

**Timeline gaps?**
→ GPU is idle
→ Can multiplex other workloads here

**Frequent small operations?**
→ API overhead
→ Batch operations together

## 🔬 For Little Boy Research

These traces reveal:

1. **Context switch points** - When GPU switches between tasks
2. **Memory patterns** - How to virtualize VRAM
3. **Scheduling decisions** - Where driver makes GPU busy/idle
4. **API overhead** - Cost of each layer
5. **Idle periods** - Where to multiplex workloads

Use this to design Little Boy's virtualization interception points.

## 🔧 Technical Details

### LD_PRELOAD Method

**What happens:**
1. Dynamic linker loads our library FIRST
2. Symbol table points to our functions
3. Our hooks log and call real functions
4. Trace written to JSONL file

**Overhead:** ~2 μs per call (< 1% for GPU operations)

**See:** `notes/tracing-mechanics.md` for complete flow diagrams

### eBPF Method

**What happens:**
1. Kernel patches functions with INT3 breakpoints
2. CPU traps to kernel on each call
3. BPF program logs call safely
4. Original instruction executes

**Overhead:** ~5 μs per call (kernel transition cost)

**See:** `notes/tracing-mechanics.md` for kernel mechanics

## 🎯 Next Steps

1. **Trace your baseline workloads:**
   ```bash
   ./trace_cuda.sh python real_time_inference.py
   ./trace_cuda.sh python batch_processing.py
   ./trace_cuda.sh python training.py
   ```

2. **Analyze results** to find patterns and bottlenecks

3. **Load binaries in Ghidra** (see `binaries/README.md`)

4. **Correlate traces** with driver behavior

5. **Design Little Boy's interception architecture**

## 📚 Further Reading

### For Understanding Hooks
1. Read `notes/tracing-quick-reference.md` - Visual diagrams
2. Read `notes/how-hooking-works.md` - LD_PRELOAD explained
3. Read `notes/tracing-mechanics.md` - Complete technical details

### For Using the Tools
1. Read `QUICK_START.md` - Usage guide
2. Run `./trace_cuda.sh --help`
3. Read `notes/getting-started.md` - Setup guide

### For Reverse Engineering
1. Read `binaries/README.md` - Ghidra analysis guide
2. Read `notes/hooking-approach.md` - Driver analysis strategy

## 💡 Key Concepts

### How LD_PRELOAD Works
```
Normal:  App → libcuda.so → GPU
Hooked:  App → libcuda_hook.so → log → libcuda.so → GPU
                     ↑ We intercept here
```

### How eBPF Works
```
App → libcuda.so (breakpoint) → TRAP → Kernel → BPF logs → Continue
                     ↑ INT3 instruction inserted here
```

### Trace Format
```jsonl
{"ts":0.001,"op_id":1,"phase":"B","name":"cuMemAlloc","details":{"size":4000000}}
{"ts":0.002,"op_id":1,"phase":"E","name":"cuMemAlloc","details":{"ptr":"0xdeadbeef"}}
```

Each operation has Begin (B) and End (E) events matched by op_id.

## 🐛 Troubleshooting

### Hook not intercepting calls

```bash
# Make sure library is built
cd hooks && make

# Check it loads
LD_PRELOAD=./libcuda_hook.so ldd $(which python)

# Enable verbose output
export CUDA_HOOK_TRACE=debug.jsonl
LD_PRELOAD=./libcuda_hook.so python test.py 2>&1 | tee log.txt
```

### eBPF not working

```bash
# Check bpftrace installed
which bpftrace

# Find libcuda.so location
find /usr /lib -name "libcuda.so*" 2>/dev/null

# Update path in trace_all_cuda.bt if needed
```

### No output

```bash
# Verify CUDA is being used
python -c "import torch; print(torch.cuda.is_available())"

# Check trace directory
ls -la traces/

# Look for errors
./trace_cuda.sh python test.py 2>&1 | grep -i error
```

## 🤝 Credits

Built for the Little Boy GPU virtualization project to establish baseline performance metrics and understand GPU scheduling behavior.

## 📄 License

Research project - see main Little Boy repository for license.
