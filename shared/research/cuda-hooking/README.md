# libcuda and NVIDIA Driver Hooking Research

## Overview

Research directory for reverse engineering libcuda and NVIDIA driver components to understand GPU scheduling mechanisms for Little Boy's virtualization layer.

## Directory Structure

```
research/libcuda-hooking/
├── binaries/          # libcuda.so and driver binaries for analysis
├── ghidra-projects/   # Ghidra project files and analysis
├── hooks/             # Hook implementation prototypes
├── notes/             # Research notes and findings
└── tools/             # Helper scripts and utilities
```

## Key Investigation Areas

### 1. libcuda.so Analysis
- CUDA API call interception points
- Function symbols and entry points
- Memory management routines
- Context switching mechanisms

### 2. NVIDIA Driver (nvidia.ko / nvidia-uvm.ko)
- IOCTL command structure
- Scheduling algorithms
- Memory allocation paths
- GPU context management

### 3. Hooking Techniques
- LD_PRELOAD interposition for userspace
- Kernel module hooking for driver level
- Function trampolines and detours
- API call tracing and instrumentation

## Tools and Resources

- **Ghidra** - Binary analysis and reverse engineering
- **strace/ltrace** - System/library call tracing
- **LD_PRELOAD** - Library interposition
- **kprobes/ftrace** - Kernel function tracing
- **CUDA GDB** - CUDA debugging and introspection

## Goals

1. Identify scheduling decision points in the driver
2. Map CUDA API calls to driver IOCTLs
3. Understand context switching overhead
4. Find interception points for workload virtualization

## Notes

- Focus on scheduling-related functions for Little Boy's virtualization
- Document all findings with addresses and function signatures
- Test hooks safely in isolated environments
