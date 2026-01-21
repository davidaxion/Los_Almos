# Hooking Approach: Tracing Inference Flow from Model Loading to Response

## Overview

To understand the complete flow from loading model weights through inference execution to getting results, you need to hook at multiple layers of the CUDA stack.

## The CUDA Stack Layers

```
┌─────────────────────────────────────────┐
│  ML Framework (PyTorch/TensorFlow)      │
│  Model.load() → forward() → output      │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  CUDA Runtime API (cudart)              │
│  cudaMalloc, cudaMemcpy, cudaLaunch     │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  CUDA Driver API (libcuda.so)           │  ← Hook here with LD_PRELOAD
│  cuMemAlloc, cuLaunchKernel, etc.       │
└────────────────┬────────────────────────┘
                 │ (IOCTL syscalls)
┌────────────────▼────────────────────────┐
│  NVIDIA Kernel Driver (nvidia.ko)       │  ← Hook here with kprobes/ftrace
│  GPU scheduler, memory manager, HW      │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  GPU Hardware                            │
│  SM execution, memory transfers          │
└─────────────────────────────────────────┘
```

## Three-Layer Hooking Strategy

### Layer 1: Userspace Library Hooks (LD_PRELOAD)

**Target**: libcuda.so functions
**Method**: LD_PRELOAD with wrapper library
**Purpose**: Track high-level operations, measure latencies

#### Key Functions to Hook

```c
// Memory Operations - Track weight loading
CUresult cuMemAlloc(CUdeviceptr *dptr, size_t bytesize);
CUresult cuMemcpyHtoD(CUdeviceptr dstDevice, const void *srcHost, size_t ByteCount);
CUresult cuMemcpyDtoH(void *dstHost, CUdeviceptr srcDevice, size_t ByteCount);

// Context Management - Track GPU context switches
CUresult cuCtxCreate(CUcontext *pctx, unsigned int flags, CUdevice dev);
CUresult cuCtxSetCurrent(CUcontext ctx);
CUresult cuCtxSynchronize(void);

// Kernel Execution - Track inference kernel launches
CUresult cuLaunchKernel(
    CUfunction f,
    unsigned int gridDimX, unsigned int gridDimY, unsigned int gridDimZ,
    unsigned int blockDimX, unsigned int blockDimY, unsigned int blockDimZ,
    unsigned int sharedMemBytes,
    CUstream hStream,
    void **kernelParams,
    void **extra
);

// Stream Management - Track async operations
CUresult cuStreamCreate(CUstream *phStream, unsigned int Flags);
CUresult cuStreamSynchronize(CUstream hStream);
```

#### Example Hook Implementation

```c
// hook_cuda.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <cuda.h>
#include <stdio.h>
#include <time.h>

static CUresult (*real_cuLaunchKernel)(CUfunction, unsigned int, unsigned int,
    unsigned int, unsigned int, unsigned int, unsigned int, unsigned int,
    CUstream, void **, void **) = NULL;

CUresult cuLaunchKernel(CUfunction f, unsigned int gridDimX, unsigned int gridDimY,
    unsigned int gridDimZ, unsigned int blockDimX, unsigned int blockDimY,
    unsigned int blockDimZ, unsigned int sharedMemBytes, CUstream hStream,
    void **kernelParams, void **extra) {

    if (!real_cuLaunchKernel) {
        real_cuLaunchKernel = dlsym(RTLD_NEXT, "cuLaunchKernel");
    }

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    printf("[HOOK] cuLaunchKernel: grid=(%u,%u,%u) block=(%u,%u,%u) shmem=%u\n",
           gridDimX, gridDimY, gridDimZ, blockDimX, blockDimY, blockDimZ, sharedMemBytes);

    CUresult result = real_cuLaunchKernel(f, gridDimX, gridDimY, gridDimZ,
                                          blockDimX, blockDimY, blockDimZ,
                                          sharedMemBytes, hStream, kernelParams, extra);

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) * 1000.0 +
                     (end.tv_nsec - start.tv_nsec) / 1000000.0;

    printf("[HOOK] cuLaunchKernel returned %d (%.3f ms)\n", result, elapsed);

    return result;
}
```

**Build and Use**:
```bash
gcc -shared -fPIC hook_cuda.c -o libhook_cuda.so -ldl -lcuda
LD_PRELOAD=./libhook_cuda.so python inference.py
```

### Layer 2: System Call Tracing (strace/ltrace)

**Target**: IOCTL calls to /dev/nvidia*
**Method**: strace to observe kernel communication
**Purpose**: See raw IOCTL commands and data flow

```bash
# Trace all IOCTL calls
strace -e ioctl -s 1000 python inference.py

# Trace CUDA library calls
ltrace -C -e '*cu*' python inference.py

# Combined: library calls and IOCTLs
ltrace -C -e '*cu*' -s 1000 python inference.py 2>&1 | tee trace.log
```

### Layer 3: Kernel-Level Tracing (ftrace/kprobes)

**Target**: nvidia.ko internal functions
**Method**: ftrace with function filter
**Purpose**: Track GPU scheduler decisions and context switches

```bash
# Enable function tracing for NVIDIA driver
echo 'nv_*' > /sys/kernel/debug/tracing/set_ftrace_filter
echo function > /sys/kernel/debug/tracing/current_tracer
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Run your workload
python inference.py

# Stop and read trace
echo 0 > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace
```

**Key kernel functions to trace** (discovered via Ghidra analysis):
- `nv_ioctl` - IOCTL handler entry point
- Scheduler functions (TBD from reverse engineering)
- Memory allocation functions
- Command submission functions

## Full Inference Flow Mapping

### Step 1: Model Loading (Weight Transfer)

**What happens**:
1. Framework reads model weights from disk
2. Allocates GPU memory via `cuMemAlloc`
3. Transfers weights via `cuMemcpyHtoD`

**Hook points**:
```
cuMemAlloc → ioctl(fd, NV_IOCTL_ALLOC_MEMORY, ...) → GPU allocator
cuMemcpyHtoD → ioctl(fd, NV_IOCTL_MEMCPY, ...) → DMA transfer
```

### Step 2: Inference Preparation

**What happens**:
1. Prepare input tensors
2. Copy input data to GPU
3. Set up kernel parameters

**Hook points**:
```
cuMemcpyHtoD (input data) → IOCTL → DMA
cuModuleGetFunction → IOCTL → kernel lookup
```

### Step 3: Kernel Execution (Inference Compute)

**What happens**:
1. Launch inference kernels (matrix multiplies, activations, etc.)
2. GPU scheduler dispatches work to SMs
3. Kernels execute on GPU

**Hook points**:
```
cuLaunchKernel → ioctl(fd, NV_IOCTL_LAUNCH, ...) → GPU scheduler → SM execution
```

### Step 4: Result Retrieval

**What happens**:
1. Synchronize to wait for completion
2. Copy results from GPU to host

**Hook points**:
```
cuStreamSynchronize → IOCTL → wait for GPU completion
cuMemcpyDtoH (output) → IOCTL → DMA read
```

## Comprehensive Instrumentation Script

```bash
#!/bin/bash
# trace_inference.sh - Full stack instrumentation

# 1. Set up kernel tracing
echo 'nv_*' > /sys/kernel/debug/tracing/set_ftrace_filter
echo function > /sys/kernel/debug/tracing/current_tracer
echo 1 > /sys/kernel/debug/tracing/tracing_on

# 2. Run inference with userspace hooks and system call tracing
LD_PRELOAD=./libhook_cuda.so strace -e ioctl -tt -T \
    python inference.py 2>&1 | tee combined_trace.log

# 3. Capture kernel trace
echo 0 > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace > kernel_trace.log

echo "Traces saved to combined_trace.log and kernel_trace.log"
```

## Analysis Workflow

1. **Run instrumentation** on a simple inference workload
2. **Correlate timestamps** across userspace, IOCTL, and kernel traces
3. **Map function calls** through the stack using Ghidra analysis
4. **Identify scheduling points** where GPU context switches occur
5. **Measure overheads** at each layer
6. **Find virtualization opportunities** where Little Boy can intercept and multiplex

## Next Steps

- [ ] Build LD_PRELOAD hook library with key CUDA functions
- [ ] Run instrumentation on simple CUDA matmul program
- [ ] Use Ghidra to map CUDA API calls to IOCTL commands
- [ ] Identify GPU scheduler functions in nvidia-kernel.o
- [ ] Measure context switching overhead
- [ ] Design Little Boy's interception architecture
