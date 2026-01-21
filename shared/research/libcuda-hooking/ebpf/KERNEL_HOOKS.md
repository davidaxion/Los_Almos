# Adding Kernel-Level Hooks to CUDA Tracing

## Overview

eBPF allows you to hook BOTH userspace (libcuda.so) AND kernel space (nvidia.ko) simultaneously. This gives you complete visibility into the full pipeline from CUDA API → Driver IOCTL → GPU Scheduler.

## Why Kernel Hooks Matter

```
USERSPACE ONLY:
  App → cuLaunchKernel() → ??? → GPU executes

USERSPACE + KERNEL:
  App → cuLaunchKernel() → ioctl(0xC0044601) → nv_ioctl_handler()
                                              → nv_queue_work()
                                              → GPU scheduler
                                              → SM execution
```

Kernel hooks reveal:
- **Scheduling decisions** - When GPU switches contexts
- **Memory management** - How VRAM is allocated at driver level
- **Command submission** - When work is queued to GPU
- **Interrupt handling** - GPU completion signals
- **Context switches** - Overhead of switching between workloads

## Current Kernel Hooks (in trace_cuda_full.bt)

### 1. IOCTL Handler
```c
kprobe:nvidia_ioctl,
kprobe:nv_ioctl
{
    // Captures entry to NVIDIA driver
    // arg1 = IOCTL command code
}
```

**What it shows:** Every call from libcuda.so to nvidia.ko

### 2. Memory Operations
```c
kprobe:nv_mem_alloc,
kprobe:os_alloc_mem
{
    // Captures GPU memory allocations at driver level
}
```

**What it shows:** Actual VRAM allocation (may differ from cuMemAlloc requests)

### 3. Scheduler Functions
```c
kprobe:nv_schedule_work,
kprobe:nv_kthread_q_schedule_q_item
{
    // Captures work queue scheduling
}
```

**What it shows:** When driver schedules work to GPU

## Finding Kernel Functions to Hook

### Method 1: List Available Kernel Functions

```bash
# Find all nvidia functions in kernel
sudo bpftrace -l 'kprobe:nv*' | head -20
sudo bpftrace -l 'kprobe:nvidia*' | head -20

# Find specific patterns
sudo bpftrace -l 'kprobe:*nvidia*ioctl*'
sudo bpftrace -l 'kprobe:*nv*mem*'
sudo bpftrace -l 'kprobe:*nv*schedule*'
```

Example output:
```
kprobe:nvidia_ioctl
kprobe:nvidia_compat_ioctl
kprobe:nv_ioctl_xfer_mode_params
kprobe:nv_mem_alloc
kprobe:nv_mem_free
kprobe:nv_schedule_work
```

### Method 2: Reverse Engineer with Ghidra

1. Load `nvidia-kernel.o` (in `../binaries/`) into Ghidra
2. Search for functions containing keywords:
   - `ioctl` - IOCTL handlers
   - `mem` or `alloc` - Memory management
   - `sched` or `queue` - Scheduling
   - `irq` or `interrupt` - GPU completion
   - `ctx` or `context` - Context management

3. Note function names and add to eBPF script

### Method 3: Dynamic Analysis

```bash
# Trace ALL kernel functions called during CUDA program
sudo bpftrace -e '
  kprobe:nv* { @calls[probe] = count(); }
  kprobe:nvidia* { @calls[probe] = count(); }
' &

# Run your CUDA program
python inference.py

# Stop tracing
sudo pkill bpftrace

# Shows which functions were actually called
```

## Key Kernel Functions to Hook

Based on reverse engineering and driver analysis, here are the most valuable hooks:

### Core IOCTL Path
```
nvidia_ioctl                     # Entry point from userspace
  └─> nv_ioctl_dispatcher        # Dispatches to specific handlers
       ├─> nv_ioctl_alloc_os_event
       ├─> nv_ioctl_alloc_memory
       ├─> nv_ioctl_free_memory
       ├─> nv_ioctl_sync_gpu_objects
       └─> nv_ioctl_graphics_object_ctrl
```

### Memory Management
```
nv_mem_alloc                     # Allocate GPU memory
nv_mem_free                      # Free GPU memory
nv_dma_map_alloc                 # DMA mapping for transfers
nv_mem_access_ok                 # Permission checks
```

### Scheduling & Execution
```
nv_schedule_work                 # Schedule work to GPU
nv_kthread_q_schedule_q_item     # Kernel thread queue scheduling
nv_dma_exec_command              # Execute DMA command
```

### Context Management
```
nv_create_context               # Create GPU context
nv_destroy_context              # Destroy GPU context
nv_bind_context_dma             # Bind context for DMA
```

### Interrupt Handling
```
nvidia_isr_kthread_bh           # Bottom-half interrupt handler
nv_kthread_q_item_init          # Initialize queue item
```

## Adding New Kernel Hooks

### Step 1: Find the Function

```bash
# Search for scheduler-related functions
sudo bpftrace -l 'kprobe:*nv*sched*'
```

### Step 2: Add to bpftrace Script

Edit `trace_cuda_full.bt`:

```c
// New hook for GPU scheduler
kprobe:nv_gpu_scheduler_schedule
{
    $event_id = @event_id;
    @event_id++;

    $ts = (nsecs - @start_time) / 1000000.0;

    printf("{\"event_id\":%d,\"ts\":%.6f,\"tid\":%d,\"type\":\"scheduler\",\"name\":\"nv_gpu_scheduler_schedule\"}\n",
           $event_id, $ts, tid);

    @scheduler_calls++;
}

// Hook with argument tracking
kprobe:nv_mem_alloc
{
    $event_id = @event_id;
    @event_id++;

    $ts = (nsecs - @start_time) / 1000000.0;
    $size = arg0;  // First argument (size)

    printf("{\"event_id\":%d,\"ts\":%.6f,\"tid\":%d,\"type\":\"kernel_mem\",\"name\":\"nv_mem_alloc\",\"size\":%d}\n",
           $event_id, $ts, tid, $size);
}
```

### Step 3: Track Entry/Exit for Timing

```c
kprobe:nv_gpu_scheduler_schedule
{
    @sched_entry[tid] = nsecs;
    // ... logging ...
}

kretprobe:nv_gpu_scheduler_schedule
{
    $entry = @sched_entry[tid];
    if ($entry > 0) {
        $duration = (nsecs - $entry) / 1000.0;  // microseconds

        $ts = (nsecs - @start_time) / 1000000.0;
        printf("{\"event_id\":%d,\"ts\":%.6f,\"tid\":%d,\"type\":\"scheduler\",\"name\":\"nv_gpu_scheduler_schedule\",\"duration_us\":%.3f}\n",
               @event_id, $ts, tid, $duration);
        @event_id++;

        delete(@sched_entry[tid]);
    }
}
```

## Correlating Userspace and Kernel Events

The trace output shows both layers:

```jsonl
{"event_id":100,"ts":10.500,"type":"userspace","name":"cuLaunchKernel","phase":"B"}
{"event_id":101,"ts":10.502,"type":"syscall","name":"ioctl","cmd":3221766657}
{"event_id":102,"ts":10.503,"type":"kernel","name":"nvidia_ioctl","phase":"B"}
{"event_id":103,"ts":10.505,"type":"scheduler","name":"nv_schedule_work"}
{"event_id":104,"ts":10.600,"type":"kernel","name":"nvidia_ioctl","phase":"E"}
{"event_id":105,"ts":10.601,"type":"userspace","name":"cuLaunchKernel","phase":"E"}
```

**Analysis:**
- `cuLaunchKernel` took 0.101ms total
- IOCTL to kernel took 0.097ms
- Scheduler was invoked during IOCTL
- Can measure overhead at each layer

## Advanced: IOCTL Command Decoding

NVIDIA IOCTLs use encoded commands. Decode them:

```c
kprobe:nvidia_ioctl
{
    $cmd = arg1;  // IOCTL command

    // Decode IOCTL (_IOC macro encoding)
    $dir = ($cmd >> 30) & 0x3;       // Direction
    $type = ($cmd >> 8) & 0xFF;      // Type ('N' for NVIDIA)
    $nr = $cmd & 0xFF;               // Number
    $size = ($cmd >> 16) & 0x3FFF;   // Size

    printf("{\"type\":\"ioctl\",\"cmd\":%u,\"decoded\":{\"dir\":%u,\"type\":%u,\"nr\":%u,\"size\":%u}}\n",
           $cmd, $dir, $type, $nr, $size);
}
```

Common NVIDIA IOCTL numbers:
- `0xC0044601` - Memory allocation
- `0xC0044602` - Memory free
- `0xC0044621` - Launch kernel
- `0xC0044630` - Synchronize

## GPU Hardware Tracepoints

Some kernels expose GPU-specific tracepoints:

```bash
# List GPU tracepoints
sudo bpftrace -l 'tracepoint:gpu:*'
sudo bpftrace -l 'tracepoint:dma_fence:*'
```

Example hooks:

```c
tracepoint:dma_fence:dma_fence_signaled
{
    // GPU completed work (fence signaled)
    printf("{\"type\":\"gpu_complete\",\"fence\":\"%s\"}\n", args->driver);
}

tracepoint:gpu:gpu_mem_total
{
    // GPU memory usage update
    printf("{\"type\":\"gpu_mem\",\"total\":%d}\n", args->total_mem_kb);
}
```

## Example: Finding Context Switch Points

To find where GPU context switches happen:

```bash
sudo bpftrace -e '
  kprobe:nv*ctx* {
    printf("%s called at %lld\n", probe, nsecs);
  }
' -c "python inference.py"
```

Then add the relevant functions to your trace script.

## Limitations and Gotchas

### 1. Function Names Vary by Driver Version

NVIDIA driver is closed-source and function names change between versions.

**Solution:** Use wildcards and fallbacks:
```c
kprobe:nvidia_ioctl,
kprobe:nv_ioctl,
kprobe:nvidia_ioctl_v2
{
    // Handle any version
}
```

### 2. Inline Functions Can't Be Probed

If a function is inlined, kprobe can't attach.

**Solution:** Hook the caller instead or use fentry/fexit (if available).

### 3. Performance Impact

Too many kprobes can slow down the kernel.

**Solution:**
- Hook only critical path functions
- Use sampling instead of tracing every call
- Disable hooks for production workloads

### 4. Arguments May Change

Driver internal APIs are unstable.

**Solution:**
- Validate arguments in Ghidra first
- Add bounds checking in eBPF code
- Handle failures gracefully

## Testing Your Kernel Hooks

```bash
# Test that hook attaches without errors
sudo bpftrace -e 'kprobe:nvidia_ioctl { printf("Hit\n"); exit(); }'

# Run small CUDA program to trigger hook
python -c "import torch; torch.cuda.init()"

# Should print "Hit" if hook works
```

## Recommended Hooks for Little Boy

For GPU virtualization research, focus on:

1. **Context Management** - `nv_create_context`, `nv_destroy_context`
   - Shows when contexts are created/destroyed
   - Overhead of context switching

2. **Memory Allocation** - `nv_mem_alloc`, `nv_mem_free`
   - VRAM allocation patterns
   - Memory pressure points

3. **Work Scheduling** - `nv_schedule_work`, `nv_kthread_q_*`
   - When GPU work is queued
   - Scheduling policy

4. **Synchronization** - `nv_wait_for_*`, `*_fence_*`
   - When CPU waits for GPU
   - Idle periods (virtualization opportunity)

## Adding Hooks to trace_cuda_full.bt

The script already includes placeholders. Just uncomment and adjust:

```bash
# Edit the script
vi trace_cuda_full.bt

# Find this section:
// GPU scheduler functions (names may vary)
kprobe:nv_schedule_work,
kprobe:nv_kthread_q_schedule_q_item
{
    # ... already implemented ...
}

# Add more functions below:
kprobe:nv_create_context
{
    # Your code here
}
```

## Next Steps

1. **Find functions:** `sudo bpftrace -l 'kprobe:nv*' | grep -i sched`
2. **Test individually:** `sudo bpftrace -e 'kprobe:FUNCTION { printf("Hit\n"); }'`
3. **Add to script:** Edit `trace_cuda_full.bt`
4. **Run full trace:** `sudo ./run_trace.sh --kernel python test.py`
5. **Analyze results:** Look for patterns and bottlenecks

## Further Reading

- [eBPF kprobe documentation](https://github.com/iovisor/bcc/blob/master/docs/reference_guide.md#1-kprobes)
- [NVIDIA driver source (open-kernel)](https://github.com/NVIDIA/open-gpu-kernel-modules)
- Our Ghidra analysis guide: `../binaries/README.md`
