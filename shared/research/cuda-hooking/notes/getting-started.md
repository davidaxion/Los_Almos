# Getting Started with libcuda Hooking Research

## Locating libcuda.so

```bash
# Find libcuda on your system
find /usr -name "libcuda.so*" 2>/dev/null
ldconfig -p | grep libcuda

# Typical locations:
# /usr/lib/x86_64-linux-gnu/libcuda.so
# /usr/lib64/libcuda.so
```

## Initial Analysis

### 1. Extract Function Symbols

```bash
# List exported symbols
nm -D /path/to/libcuda.so | grep -i cuda

# View dynamic dependencies
ldd /path/to/libcuda.so

# Check CUDA API functions
objdump -T /path/to/libcuda.so | grep cuda
```

### 2. Trace CUDA Calls

```bash
# Trace library calls from a CUDA program
ltrace -C -e '*cuda*' ./your_cuda_program

# Trace system calls (IOCTLs to driver)
strace -e ioctl ./your_cuda_program
```

### 3. Load in Ghidra

1. Import libcuda.so into new Ghidra project
2. Analyze with default analyzers
3. Search for key functions:
   - `cuLaunchKernel`
   - `cuCtxCreate`
   - `cuMemAlloc`
   - `cuStreamCreate`
   - Scheduler-related symbols

## Key Functions to Investigate

### Scheduling and Execution
- `cuLaunchKernel` - Kernel launch entry point
- `cuLaunchCooperativeKernel` - Cooperative group launches
- `cuStreamCreate` - Stream management
- `cuStreamSynchronize` - Synchronization points

### Context Management
- `cuCtxCreate` - Context creation
- `cuCtxSetCurrent` - Context switching
- `cuCtxSynchronize` - Context synchronization

### Memory Operations
- `cuMemAlloc` - Memory allocation
- `cuMemcpy*` - Memory transfers
- `cuMemGetInfo` - Memory queries

## Hook Implementation Strategy

1. **LD_PRELOAD approach** - Intercept CUDA API calls before they reach libcuda
2. **Function wrapping** - Wrap target functions to inject custom logic
3. **Measurement points** - Add timing and resource tracking
4. **Driver analysis** - Map API calls to kernel IOCTLs

## Next Steps

- [ ] Copy libcuda.so to binaries/ directory
- [ ] Create Ghidra project in ghidra-projects/
- [ ] Document function addresses and signatures
- [ ] Build simple LD_PRELOAD hook prototype
- [ ] Trace CUDA program execution with strace/ltrace
