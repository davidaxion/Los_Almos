# CUDA Tracing - Quick Visual Reference

## TL;DR - How It Works in 30 Seconds

### LD_PRELOAD Method
```
You run: LD_PRELOAD=./libcuda_hook.so python script.py

What happens:
1. Linux loads libcuda_hook.so FIRST
2. Your code calls cuLaunchKernel()
3. Goes to OUR function (not real libcuda.so)
4. We log: timestamp, parameters
5. We call REAL cuLaunchKernel()
6. We log: return value, duration
7. Return to your code

Result: Every CUDA call logged to trace file
```

### eBPF Method
```
You run: sudo bpftrace trace_all_cuda.bt

What happens:
1. Kernel patches libcuda.so functions with breakpoints
2. Your code calls cuLaunchKernel()
3. CPU hits breakpoint → traps to kernel
4. Kernel runs our BPF program (logs call)
5. Kernel executes original instruction
6. Returns to userspace

Result: Every CUDA call logged, no library modification
```

## Visual Comparison

### Normal CUDA Call (No Tracing)
```
┌──────────────┐
│ Your App     │
└──────┬───────┘
       │ cuLaunchKernel()
       ↓
┌──────────────┐
│ libcuda.so   │
└──────┬───────┘
       │ ioctl()
       ↓
┌──────────────┐
│ nvidia.ko    │
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ GPU          │
└──────────────┘

Time: ~10 microseconds
```

### With LD_PRELOAD Tracing
```
┌──────────────┐
│ Your App     │
└──────┬───────┘
       │ cuLaunchKernel()
       ↓
┌──────────────────────┐
│ libcuda_hook.so      │
│ ┌────────────────┐   │
│ │ LOG START      │   │ +2 μs overhead
│ │ ts = now()     │   │
│ └────────────────┘   │
└──────┬───────────────┘
       │ real_cuLaunchKernel()
       ↓
┌──────────────┐
│ libcuda.so   │
└──────┬───────┘
       │ ioctl()
       ↓
┌──────────────┐
│ nvidia.ko    │
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ GPU          │
└──────┬───────┘
       │ returns
       ↓
┌──────────────────────┐
│ libcuda_hook.so      │
│ ┌────────────────┐   │
│ │ LOG END        │   │ +2 μs overhead
│ │ duration = ... │   │
│ └────────────────┘   │
└──────┬───────────────┘
       │
       ↓
┌──────────────┐
│ Your App     │
└──────────────┘

Time: ~14 microseconds (minimal overhead!)
Trace: {"ts":123.456,"op_id":1,"phase":"B","name":"cuLaunchKernel"}
       {"ts":123.470,"op_id":1,"phase":"E","name":"cuLaunchKernel"}
```

### With eBPF Tracing
```
┌──────────────┐
│ Your App     │
└──────┬───────┘
       │ cuLaunchKernel()
       ↓
┌──────────────────────┐
│ libcuda.so           │
│ 0x7f12340000: 0xCC   │ ← Breakpoint (INT3)
└──────┬───────────────┘
       │ INT3 trap
       ↓
╔══════════════════════╗
║ KERNEL MODE          ║
║ ┌────────────────┐   ║
║ │ BPF Program    │   ║  +5 μs overhead
║ │ LOG: probe hit │   ║  (kernel transition)
║ │ Execute orig   │   ║
║ └────────────────┘   ║
╚══════┬═══════════════╝
       │ return to userspace
       ↓
┌──────────────┐
│ libcuda.so   │ (continues normally)
└──────┬───────┘
       │ ioctl()
       ↓
┌──────────────┐
│ nvidia.ko    │
└──────┬───────┘
       │
       ↓
┌──────────────┐
│ GPU          │
└──────────────┘

Time: ~15 microseconds
Trace: Kernel ring buffer → bpftrace → output
```

## Symbol Resolution (LD_PRELOAD Magic)

### Without LD_PRELOAD
```
Dynamic Linker builds symbol table:

Symbol: cuLaunchKernel
Search in loaded libraries:
  1. libcuda.so → FOUND at 0x7f123456789a

Global Offset Table (GOT):
  cuLaunchKernel → 0x7f123456789a

When you call cuLaunchKernel():
  jmp *GOT[cuLaunchKernel]
  → Goes to 0x7f123456789a (real function)
```

### With LD_PRELOAD
```
Dynamic Linker builds symbol table:

LD_PRELOAD=./libcuda_hook.so

Symbol: cuLaunchKernel
Search in loaded libraries (IN ORDER):
  1. libcuda_hook.so → FOUND at 0x7f111111aaaa ✓ STOP HERE!
  2. (libcuda.so not checked, already found)

Global Offset Table (GOT):
  cuLaunchKernel → 0x7f111111aaaa

When you call cuLaunchKernel():
  jmp *GOT[cuLaunchKernel]
  → Goes to 0x7f111111aaaa (OUR hook!)

Our hook uses dlsym(RTLD_NEXT):
  "Find NEXT cuLaunchKernel after libcuda_hook.so"
  → Finds 0x7f123456789a in libcuda.so
  → Calls it directly
```

## Memory Layout Comparison

### Library Load Order
```
Without LD_PRELOAD:
┌─────────────────────────┐ 0x7fff00000000
│ Stack                   │
├─────────────────────────┤ 0x7f5555555000
│ libc.so                 │
├─────────────────────────┤ 0x7f3456780000
│ libcuda.so              │ ← cuLaunchKernel here
│ - cuLaunchKernel ───────┼──→ GOT points here
├─────────────────────────┤
│ libpython.so            │
├─────────────────────────┤ 0x555555554000
│ python (main program)   │
└─────────────────────────┘ 0x400000

With LD_PRELOAD:
┌─────────────────────────┐ 0x7fff00000000
│ Stack                   │
├─────────────────────────┤ 0x7f5555555000
│ libc.so                 │
├─────────────────────────┤ 0x7f3456780000
│ libcuda.so              │ ← Real function (not used initially)
│ - cuLaunchKernel        │
├─────────────────────────┤ 0x7f1111110000
│ libcuda_hook.so         │ ← Our hook (loaded FIRST)
│ - cuLaunchKernel ───────┼──→ GOT points here!
├─────────────────────────┤
│ libpython.so            │
├─────────────────────────┤ 0x555555554000
│ python (main program)   │
└─────────────────────────┘ 0x400000
```

## Trace File Format

### JSON Lines (JSONL)
```jsonl
{"ts":0.000001,"op_id":0,"phase":"B","name":"cuInit","details":{"flags":0}}
{"ts":0.000050,"op_id":0,"phase":"E","name":"cuInit","details":{"status":0}}
```

Each line is independent JSON:
- `ts`: Timestamp (seconds since start)
- `op_id`: Matches begin/end events
- `phase`: "B" = begin, "E" = end
- `name`: Function name
- `details`: Optional metadata

### Processing
```python
# visualize_pipeline.py

# Read file
for line in open("trace.jsonl"):
    event = json.loads(line)

    if event['phase'] == 'B':
        # Start operation
        stack[event['op_id']] = event
    else:
        # End operation
        start = stack.pop(event['op_id'])
        duration = event['ts'] - start['ts']

        operations.append({
            'name': event['name'],
            'start': start['ts'],
            'duration': duration
        })

# Now analyze operations...
```

## Three Methods - When to Use Which?

### LD_PRELOAD
```
✓ Best for: Detailed timing, no root needed
✓ Pros: Low overhead, rich data, easy to modify
✗ Cons: Must list functions explicitly (or use many hooks)

Use when:
- You want precise timing of CUDA operations
- You don't have root access
- You want to modify behavior (not just observe)
```

### eBPF
```
✓ Best for: Automatically hook everything, production systems
✓ Pros: Hooks ALL functions, no app modification, safe
✗ Cons: Requires root, higher overhead, kernel version dependent

Use when:
- You want to hook EVERYTHING without listing functions
- You're tracing live production workloads
- You need system-wide visibility
```

### strace
```
✓ Best for: Understanding kernel driver communication
✓ Pros: Shows exact IOCTLs, no library needed
✗ Cons: High overhead, low-level data, hard to interpret

Use when:
- You want to see how libcuda.so talks to nvidia.ko
- You're debugging driver issues
- You want to understand IOCTL protocol
```

## Performance Comparison

```
Operation: cuLaunchKernel (fast operation)

No tracing:        10 μs  ████████████
LD_PRELOAD:        12 μs  ██████████████          +20%
eBPF:              15 μs  ██████████████████      +50%
strace:            50 μs  ████████████████████████████████████████  +400%

Operation: GPU compute (slow operation, 1ms)

No tracing:      1000 μs  ████████████
LD_PRELOAD:      1002 μs  ████████████            +0.2%
eBPF:            1005 μs  ████████████            +0.5%
strace:          1050 μs  ████████████▌           +5%

Conclusion: Overhead matters for fast ops, negligible for GPU work
```

## Quick Cheat Sheet

### Run LD_PRELOAD Trace
```bash
cd research/libcuda-hooking/tools
./trace_cuda.sh python your_script.py
# Output: traces/trace_TIMESTAMP_ld_preload.jsonl
```

### Run eBPF Trace
```bash
sudo ./trace_cuda.sh --method=ebpf python your_script.py
# Output: traces/trace_TIMESTAMP_ebpf.log
```

### Visualize
```bash
python visualize_pipeline.py trace.jsonl
# Shows: ASCII timeline, statistics, top operations
```

### View in Chrome
```bash
python visualize_pipeline.py --format=chrome trace.jsonl
# Open trace.json in chrome://tracing
```

## What You Get

```
INPUT:  Your CUDA application
OUTPUT: Complete execution pipeline with:

1. Timeline of all CUDA calls
2. Time breakdown by category
3. Bottleneck identification
4. Call hierarchy (depth)
5. Memory transfer analysis
6. Kernel launch patterns

Use this to:
- Find where time is spent
- Identify optimization opportunities
- Understand GPU scheduling
- Design virtualization layer
```

## The Magic Explained in One Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ How does LD_PRELOAD let us intercept function calls?       │
└─────────────────────────────────────────────────────────────┘

Step 1: Program starts
  kernel → load ld.so (dynamic linker)

Step 2: ld.so reads LD_PRELOAD
  ld.so → "Ah! Load libcuda_hook.so FIRST!"

Step 3: ld.so builds symbol table
  Search order: LD_PRELOAD libs → regular libs
  cuLaunchKernel found in libcuda_hook.so → use this address

Step 4: Your code calls cuLaunchKernel
  call *[GOT+offset] → jumps to libcuda_hook.so

Step 5: Our hook runs
  log() → call real function → log() → return

That's it! No magic, just library load order.
```
