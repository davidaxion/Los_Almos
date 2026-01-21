# How CUDA API Hooking Works

## The Basic Concept

When your Python/C++ program calls CUDA functions, it goes through several layers:

```
Your Application (Python/C++)
         ↓
   CUDA Runtime API (libcudart.so) [optional layer]
         ↓
   CUDA Driver API (libcuda.so) ← WE HOOK HERE
         ↓
   Kernel Driver (nvidia.ko)
         ↓
   GPU Hardware
```

## Method 1: LD_PRELOAD (Symbol Interposition)

### How It Works

Linux uses **dynamic linking** - when your program starts, the dynamic linker loads shared libraries and resolves function symbols.

```bash
# Normal execution
python inference.py
  → Loads libcuda.so
  → Calls cuLaunchKernel from libcuda.so

# With LD_PRELOAD
LD_PRELOAD=./libcuda_hook.so python inference.py
  → Loads libcuda_hook.so FIRST
  → Loads libcuda.so
  → Calls cuLaunchKernel from libcuda_hook.so (our hook)
  → Our hook calls real cuLaunchKernel from libcuda.so
```

### Step-by-Step Flow

1. **Application calls `cuLaunchKernel()`**
   ```python
   # In PyTorch
   torch.matmul(a, b)  # Internally calls CUDA
   ```

2. **Dynamic linker resolves the symbol**
   - Normally: finds `cuLaunchKernel` in `libcuda.so`
   - With LD_PRELOAD: finds `cuLaunchKernel` in `libcuda_hook.so` first

3. **Our hook function executes**
   ```c
   CUresult cuLaunchKernel(...) {
       // 1. Log entry + timestamp
       printf("ENTER cuLaunchKernel at time=%f\n", get_time());

       // 2. Call the REAL function
       CUresult result = real_cuLaunchKernel(...);

       // 3. Log exit + result
       printf("EXIT cuLaunchKernel result=%d time=%f\n", result, get_time());

       return result;  // Pass result back to application
   }
   ```

4. **Getting the real function**
   ```c
   // Use dlsym with RTLD_NEXT to find the next symbol in the chain
   real_cuLaunchKernel = dlsym(RTLD_NEXT, "cuLaunchKernel");
   ```

### Visual Representation

```
Application code:
├─ cuLaunchKernel() ──┐
                       │
                       ↓
LD_PRELOAD hook:
├─ OUR cuLaunchKernel() {
│    ├─ [LOG] "Entering cuLaunchKernel..."
│    ├─ timestamp_start = now()
│    │
│    ├─ result = real_cuLaunchKernel() ──┐
│    │                                    │
│    │                                    ↓
│    │                           Real libcuda.so:
│    │                           ├─ cuLaunchKernel() {
│    │                           │    ├─ Validate parameters
│    │                           │    ├─ ioctl() to nvidia.ko
│    │                           │    └─ return status
│    │                           └─ }
│    │                                    │
│    ├─ [receives result] ←──────────────┘
│    │
│    ├─ timestamp_end = now()
│    ├─ [LOG] "Exiting cuLaunchKernel, took 0.5ms"
│    └─ return result
│  }
│
└─ [Application receives result]
```

## Method 2: Function Trampolines (More Advanced)

Instead of LD_PRELOAD, directly patch the function:

```c
// 1. Find cuLaunchKernel in memory
void* target = dlsym(RTLD_DEFAULT, "cuLaunchKernel");

// 2. Make memory writable
mprotect(target, size, PROT_READ | PROT_WRITE | PROT_EXEC);

// 3. Write a JMP instruction to our hook
write_jmp(target, our_hook_function);

// 4. Our hook calls original code we saved
```

This is more complex but doesn't require LD_PRELOAD.

## Method 3: Generic Hooking (Intercept Everything)

Instead of hardcoding every CUDA function, we can intercept dynamically:

### Approach A: dlsym Interception

Override `dlsym` itself to intercept symbol resolution:

```c
void* dlsym(void* handle, const char* symbol) {
    // Get real symbol
    void* real_func = REAL_dlsym(handle, symbol);

    // If it's a CUDA function (starts with "cu")
    if (strncmp(symbol, "cu", 2) == 0) {
        printf("Intercepting: %s\n", symbol);

        // Return wrapper instead of real function
        return create_wrapper(symbol, real_func);
    }

    return real_func;
}
```

Problem: We don't know the function signature, so we can't call it properly.

### Approach B: Assembly-Level Trampoline

Create a generic wrapper in assembly:

```asm
; Generic hook that works for any function
generic_hook:
    ; Save all registers
    push rax, rbx, rcx, rdx, rsi, rdi, ...

    ; Log function entry
    call log_entry

    ; Restore registers
    pop ...

    ; Call original function
    call [real_function_ptr]

    ; Save return value
    push rax

    ; Log function exit
    call log_exit

    ; Restore and return
    pop rax
    ret
```

### Approach C: eBPF + uprobes (Best for Generic Hooking)

Use Linux kernel's eBPF to trace user-space functions:

```bash
# Attach uprobe to every function in libcuda.so
bpftrace -e '
  uprobe:/lib/x86_64-linux-gnu/libcuda.so:cu* {
    printf("ENTER: %s\n", probe);
  }

  uretprobe:/lib/x86_64-linux-gnu/libcuda.so:cu* {
    printf("EXIT: %s (retval=%d)\n", probe, retval);
  }
'
```

This automatically hooks ALL functions matching the pattern!

## Method 4: System Call Tracing (strace)

Hook at the kernel boundary instead:

```bash
strace -e ioctl python inference.py
```

This shows all ioctl() calls to /dev/nvidia*, which is how libcuda.so talks to the kernel driver.

Example output:
```
ioctl(3, NV_IOCTL_ALLOC_MEMORY, {...}) = 0
ioctl(3, NV_IOCTL_LAUNCH_KERNEL, {...}) = 0
```

## Complete Hooking Stack

For a full pipeline view, combine multiple methods:

```
┌─────────────────────────────────────────┐
│  Application (PyTorch)                  │
│  torch.matmul(a, b)                     │
└───────────────┬─────────────────────────┘
                │
                ↓ [Hook Layer 1: LD_PRELOAD]
┌─────────────────────────────────────────┐
│  libcuda_hook.so                        │
│  Intercepts: cuLaunchKernel()           │
│  Logs: "cuLaunchKernel called"          │
└───────────────┬─────────────────────────┘
                │
                ↓ [Real CUDA Library]
┌─────────────────────────────────────────┐
│  libcuda.so                             │
│  Real cuLaunchKernel() implementation   │
└───────────────┬─────────────────────────┘
                │
                ↓ [Hook Layer 2: strace]
┌─────────────────────────────────────────┐
│  System Call: ioctl()                   │
│  Logs: "ioctl(fd, LAUNCH_KERNEL, ...)"  │
└───────────────┬─────────────────────────┘
                │
                ↓ [Kernel Space]
┌─────────────────────────────────────────┐
│  nvidia.ko driver                       │
│  GPU scheduler, memory manager          │
└───────────────┬─────────────────────────┘
                │
                ↓ [Hook Layer 3: ftrace/eBPF]
┌─────────────────────────────────────────┐
│  Kernel Functions                       │
│  Logs: "nv_ioctl_handler()"             │
└───────────────┬─────────────────────────┘
                │
                ↓
┌─────────────────────────────────────────┐
│  GPU Hardware                           │
└─────────────────────────────────────────┘
```

## Why This Matters for Little Boy

By hooking at different layers, we can:

1. **Userspace (LD_PRELOAD)**: See what operations applications request
2. **Syscall (strace)**: See how libcuda translates to kernel commands
3. **Kernel (ftrace)**: See GPU scheduler decisions

This reveals:
- Where GPU context switches happen
- How memory is allocated and transferred
- When the GPU is idle (scheduling opportunities)
- Overhead of each layer

## Practical Example

Let's trace a simple matrix multiply:

```python
# inference.py
import torch
a = torch.randn(1000, 1000).cuda()
b = torch.randn(1000, 1000).cuda()
c = torch.matmul(a, b)
print(c)
```

With hooks enabled:
```bash
LD_PRELOAD=./libcuda_hook.so python inference.py
```

Output trace:
```
[0.000001] cuInit(flags=0)
[0.000050] cuDeviceGet(device=0)
[0.000102] cuCtxCreate(flags=0, device=0x7f...)
[0.001234] cuMemAlloc(size=4000000) → ptr=0xdeadbeef
[0.001456] cuMemAlloc(size=4000000) → ptr=0xcafebabe
[0.001890] cuMemcpyHtoD(dst=0xdeadbeef, size=4000000, bw=12.3 GB/s)
[0.015670] cuMemcpyHtoD(dst=0xcafebabe, size=4000000, bw=11.8 GB/s)
[0.029450] cuLaunchKernel(grid=[31,31,1], block=[32,32,1], threads=998912)
[0.029480] cuCtxSynchronize() → waited 5.2ms
[0.034720] cuMemcpyDtoH(src=0xresult, size=4000000, bw=13.1 GB/s)
```

Now we can see the **complete pipeline**:
1. Initialize CUDA → 0.05ms
2. Allocate matrices → 0.36ms
3. Transfer data to GPU → 13.8ms
4. Execute kernel → 5.2ms
5. Transfer result back → 5.3ms
**Total: ~24.7ms**

We can identify:
- Data transfer is the bottleneck (77% of time)
- Kernel execution is fast (21% of time)
- Opportunities for batching, pipelining, or memory reuse
