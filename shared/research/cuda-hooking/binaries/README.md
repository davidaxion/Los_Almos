# Downloaded NVIDIA Binaries for Analysis

## Files

### libcuda.so (92MB)
- **Version**: 580.126.09
- **Type**: CUDA Runtime Library (userspace)
- **Architecture**: x86_64 Linux
- **Description**: Main CUDA API implementation library that applications link against

**Key Functions to Analyze:**
- `cuLaunchKernel` - Kernel launch entry point
- `cuCtxCreate` / `cuCtxSetCurrent` - Context management
- `cuStreamCreate` / `cuStreamSynchronize` - Stream operations
- `cuMemAlloc` / `cuMemcpy*` - Memory management
- CUDA driver API wrappers that communicate with kernel driver

### nvidia-kernel.o (107MB)
- **Version**: 580.126.09
- **Type**: NVIDIA Kernel Driver Binary Blob (kernel space)
- **Architecture**: x86_64 Linux
- **Source**: nv-kernel.o_binary from proprietary driver package
- **Description**: Core proprietary kernel driver implementation containing GPU scheduling, memory management, and hardware control logic

**Key Areas to Investigate:**
- IOCTL handler implementations
- GPU scheduler algorithms
- Context switching mechanisms
- Memory allocator
- Command submission paths
- Interrupt handlers

## Source Package

Downloaded from: https://download.nvidia.com/XFree86/Linux-x86_64/580.126.09/NVIDIA-Linux-x86_64-580.126.09.run

## Analysis Workflow

1. **Load in Ghidra**
   - Create separate projects for libcuda.so and nvidia-kernel.o
   - Analyze with default options
   - Focus on exported symbols for libcuda.so
   - Look for IOCTL handlers in nvidia-kernel.o

2. **Cross-Reference**
   - Map CUDA API calls in libcuda.so to IOCTL calls
   - Trace data flow from userspace to kernel
   - Identify scheduling decision points

3. **Hook Points**
   - Userspace: LD_PRELOAD hooks on CUDA API functions
   - Kernel space: kprobe/ftrace on key kernel functions
   - System call tracing: strace to observe IOCTL patterns

## Notes

- The nvidia-kernel.o file is the precompiled binary blob, not a complete .ko module
- The final nvidia.ko module is created by linking this binary with open-source wrapper code
- For runtime analysis, you'll need a Linux system with NVIDIA GPU and matching driver version
- Both files contain position-independent code suitable for static analysis in Ghidra
