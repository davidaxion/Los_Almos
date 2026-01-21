# How CUDA Tracing Actually Works - Deep Dive

## Overview: The Three Tracing Methods

```
┌─────────────────────────────────────────────────────────────┐
│ Application Process Memory Space                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Your Code (Python/C++)                                     │
│     ↓ calls cuLaunchKernel()                                │
│                                                             │
│  [METHOD 1: LD_PRELOAD]                                     │
│  ┌──────────────────────────────────┐                       │
│  │ libcuda_hook.so (loaded first)   │ ← Intercepts here    │
│  │ - Our cuLaunchKernel() wrapper   │                       │
│  └──────────────────────────────────┘                       │
│     ↓ calls real function                                   │
│  ┌──────────────────────────────────┐                       │
│  │ libcuda.so (real CUDA library)   │                       │
│  │ - Real cuLaunchKernel()          │ ← [METHOD 2: eBPF]   │
│  └──────────────────────────────────┘   uprobe attached    │
│     ↓ makes syscall                                         │
├─────────────────────────────────────────────────────────────┤
│                   Kernel Space                              │
├─────────────────────────────────────────────────────────────┤
│  ioctl() system call                     ← [METHOD 3: strace]
│     ↓                                      traces this      │
│  nvidia.ko driver                                           │
│     ↓                                                       │
│  GPU Hardware                                               │
└─────────────────────────────────────────────────────────────┘
```

## Method 1: LD_PRELOAD - Step by Step

### Phase 1: Program Startup - Dynamic Linker Magic

When you run: `LD_PRELOAD=./libcuda_hook.so python inference.py`

**Step 1: Process Creation**
```bash
execve("python", ["python", "inference.py"], env)
```

**Step 2: Kernel Loads the ELF Binary**
```
Kernel:
  - Reads Python ELF header
  - Finds interpreter: /lib64/ld-linux-x86-64.so.2 (dynamic linker)
  - Maps dynamic linker into memory
  - Jumps to dynamic linker entry point
```

**Step 3: Dynamic Linker Initialization**
```c
// Inside ld.so (the dynamic linker)

1. Read LD_PRELOAD environment variable
   → Found: "./libcuda_hook.so"

2. Load libraries in order:
   a) LD_PRELOAD libraries FIRST
   b) Program's dependencies
   c) Recursive dependencies

3. For each library:
   - mmap() the .so file into memory
   - Parse ELF sections
   - Build symbol table
```

**Step 4: Symbol Resolution**

This is where the magic happens!

```c
// Dynamic linker resolves symbols

Symbol needed: "cuLaunchKernel"

Search order:
1. Check LD_PRELOAD libraries first
   → libcuda_hook.so exports "cuLaunchKernel" ✓ FOUND!
   → Store address: 0x7f1234abcd00

2. (Would check libcuda.so, but already found)

Result: All calls to cuLaunchKernel → 0x7f1234abcd00 (our hook)
```

**Visual Memory Layout After Loading:**
```
Memory Address Space:
┌─────────────────────────────────────┐
│ 0x7fff00000000  Stack               │
├─────────────────────────────────────┤
│ 0x7f5678900000  libc.so             │
│ 0x7f5555550000  libpython3.so       │
│ 0x7f3456780000  libcuda.so          │ ← Real CUDA library
│                 - cuLaunchKernel at │
│                   0x7f3456781234    │
│ 0x7f1234000000  libcuda_hook.so     │ ← Our hook (loaded first!)
│                 - cuLaunchKernel at │
│                   0x7f1234abcd00    │ ← Symbol table points here
├─────────────────────────────────────┤
│ 0x555555554000  python binary       │
│ 0x400000        Program code        │
└─────────────────────────────────────┘
```

### Phase 2: Runtime - Hook Execution

**What Happens When Your Code Calls cuLaunchKernel()**

```python
# Your Python code
import torch
x = torch.randn(10, 10).cuda()
y = torch.matmul(x, x)  # This triggers cuLaunchKernel internally
```

**Step 1: PLT/GOT Lookup**
```asm
; Compiled code for the call
call cuLaunchKernel@PLT

; PLT (Procedure Linkage Table) entry:
cuLaunchKernel@PLT:
    jmp *cuLaunchKernel@GOT    ; Jump to address in GOT

; GOT (Global Offset Table) contains:
cuLaunchKernel@GOT: 0x7f1234abcd00   ; Our hook address (from dynamic linker)
```

**Step 2: Our Hook Executes**
```c
// libcuda_hook.so: hooks/cuda_hook.c

CUresult cuLaunchKernel(CUfunction f, ...) {
    // 1. ENTRY LOGGING
    uint64_t op_id = next_op_id();        // op_id = 42
    double start = get_timestamp();        // start = 123.456789

    // Write to trace file: cuda_trace.jsonl
    fprintf(trace_file,
            "{\"ts\":%.9f,\"op_id\":%llu,\"phase\":\"B\",\"name\":\"cuLaunchKernel\"}\n",
            start, op_id);
    // Output: {"ts":123.456789000,"op_id":42,"phase":"B","name":"cuLaunchKernel"}

    // 2. CALL REAL FUNCTION
    // We need the REAL cuLaunchKernel from libcuda.so
    CUresult result = real_cuLaunchKernel(f, ...);

    // 3. EXIT LOGGING
    double end = get_timestamp();          // end = 123.457234
    fprintf(trace_file,
            "{\"ts\":%.9f,\"op_id\":%llu,\"phase\":\"E\",\"name\":\"cuLaunchKernel\",\"result\":%d}\n",
            end, op_id, result);
    // Output: {"ts":123.457234000,"op_id":42,"phase":"E","name":"cuLaunchKernel","result":0}

    // 4. RETURN TO CALLER
    return result;
}
```

**Step 3: Getting the Real Function**

How do we get `real_cuLaunchKernel`?

```c
// One-time initialization (first call only)
static CUresult (*real_cuLaunchKernel)(...) = NULL;

if (!real_cuLaunchKernel) {
    // dlsym with RTLD_NEXT means:
    // "Find the NEXT symbol after the current library"
    real_cuLaunchKernel = dlsym(RTLD_NEXT, "cuLaunchKernel");
}

// Now real_cuLaunchKernel points to: 0x7f3456781234 (libcuda.so)
```

**Visual Call Flow:**
```
1. Your Code
   call cuLaunchKernel
     ↓
2. PLT/GOT Jump
   jmp 0x7f1234abcd00
     ↓
3. Our Hook (libcuda_hook.so)
   ┌─────────────────────────────────┐
   │ Log entry: time, params         │
   │ real_cuLaunchKernel(...)        │ ─────┐
   └─────────────────────────────────┘      │
     ↑                                       │
     │ Return                                │
     │                                       ↓
   ┌─────────────────────────────────┐   Direct call
   │ Log exit: time, result          │   0x7f3456781234
   └─────────────────────────────────┘      ↓
                                       4. Real libcuda.so
                                       ┌─────────────────────────────────┐
                                       │ cuLaunchKernel(...)             │
                                       │ - Validate parameters           │
                                       │ - Build IOCTL command           │
                                       │ - syscall(ioctl, ...)           │
                                       │ - Return status                 │
                                       └─────────────────────────────────┘
```

### Phase 3: Trace File Generation

**During Execution:**
```jsonl
{"ts":0.000123,"op_id":0,"phase":"B","name":"cuInit"}
{"ts":0.000456,"op_id":0,"phase":"E","name":"cuInit","result":0}
{"ts":0.001234,"op_id":1,"phase":"B","name":"cuMemAlloc","details":{"size":4000000}}
{"ts":0.001890,"op_id":1,"phase":"E","name":"cuMemAlloc","details":{"ptr":"0xdeadbeef"}}
{"ts":0.015670,"op_id":2,"phase":"B","name":"cuMemcpyHtoD"}
{"ts":0.029450,"op_id":2,"phase":"E","name":"cuMemcpyHtoD","details":{"bandwidth_gbps":12.3}}
{"ts":0.029480,"op_id":3,"phase":"B","name":"cuLaunchKernel"}
{"ts":0.029503,"op_id":3,"phase":"E","name":"cuLaunchKernel","result":0}
```

**Each line is a JSON object:**
- `ts`: Timestamp in seconds since program start
- `op_id`: Unique operation ID (matches begin/end)
- `phase`: "B" = Begin, "E" = End
- `name`: Function name
- `details`: Additional info (parameters, results)

## Method 2: eBPF/uprobes - How It Works

### Phase 1: Attaching uprobes

When you run: `sudo bpftrace trace_all_cuda.bt`

**Step 1: Parse BPF Script**
```c
// From trace_all_cuda.bt
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cu*
```

BPFtrace compiler translates this to:
```c
// Find all symbols matching pattern "cu*" in libcuda.so
symbols = get_symbols("/lib/x86_64-linux-gnu/libcuda.so.1", "cu*");
// Results: cuInit, cuDeviceGet, cuMemAlloc, cuLaunchKernel, ... (hundreds!)

for each symbol:
    attach_uprobe(symbol);
```

**Step 2: Kernel Sets Up Probes**

For each function (e.g., cuLaunchKernel at 0x7f3456781234):

```c
// Inside the kernel

1. Save original instruction at 0x7f3456781234:
   original_bytes = *0x7f3456781234;  // e.g., "push %rbp"

2. Replace with INT3 (breakpoint):
   *0x7f3456781234 = 0xCC;  // INT3 instruction

3. Register handler:
   uprobe_handlers[0x7f3456781234] = bpf_program;
```

**Memory Before/After:**
```
libcuda.so before:
0x7f3456781234: 55                 push   %rbp      ← cuLaunchKernel entry
0x7f3456781235: 48 89 e5           mov    %rsp,%rbp
0x7f3456781238: 48 83 ec 20        sub    $0x20,%rsp
...

libcuda.so after uprobe attached:
0x7f3456781234: CC                 int3             ← BREAKPOINT!
0x7f3456781235: 48 89 e5           mov    %rsp,%rbp
0x7f3456781238: 48 83 ec 20        sub    $0x20,%rsp
```

### Phase 2: Runtime - Probe Fires

**When cuLaunchKernel is called:**

```
1. CPU executes: call 0x7f3456781234
2. CPU fetches instruction at 0x7f3456781234
3. Finds: 0xCC (INT3 = software interrupt)
4. CPU traps to kernel
```

**In Kernel Mode:**
```c
// Kernel interrupt handler

int3_handler() {
    // 1. CPU is now in kernel mode
    rip = %rip;  // Instruction pointer = 0x7f3456781234

    // 2. Look up probe handler
    handler = uprobe_handlers[rip];

    // 3. Execute BPF program
    if (handler) {
        // Save CPU state
        context.rdi = %rdi;  // First argument
        context.rsi = %rsi;  // Second argument
        // ... all registers

        // Run BPF program in safe VM
        bpf_vm_execute(handler, &context);
        // Our BPF program logs: timestamp, function name, etc.
    }

    // 4. Execute original instruction
    execute_instruction(original_bytes[rip]);

    // 5. Return to user mode
    return_to_userspace();
}
```

**BPF Program Execution:**
```c
// Our BPF program (from trace_all_cuda.bt)

uprobe:/lib/*/libcuda.so*:cu* {
    // We're in BPF VM, very restricted environment

    // Safe operations allowed:
    @entry_ts[tid, probe] = nsecs;          // Store timestamp
    printf("→ %s\n", probe);                // Print to trace buffer

    // Unsafe operations NOT allowed:
    // - Can't call arbitrary functions
    // - Can't access arbitrary memory
    // - Limited stack size
    // - Must be verifiable by kernel
}
```

**Visual Flow:**
```
User Space:
  call cuLaunchKernel
    ↓
  CPU fetches 0xCC (INT3)
    ↓
  [TRAP TO KERNEL]
    ↓
Kernel Space:
  ┌─────────────────────────────────┐
  │ INT3 Handler                    │
  │ - Find uprobe for this address  │
  │ - Execute BPF program           │
  │   • Log timestamp               │
  │   • Store in ring buffer        │
  │ - Execute original instruction  │
  └─────────────────────────────────┘
    ↓
  [RETURN TO USER SPACE]
    ↓
User Space:
  Continue in cuLaunchKernel
```

### Phase 3: Return Probe (uretprobe)

Return probes work differently:

```c
// On function entry (uprobe):
1. Save return address from stack: ret_addr = *(rsp)
2. Replace return address with trampoline: *(rsp) = trampoline_addr
3. Store original return address

// Function executes normally...

// On function exit (return instruction):
1. CPU returns to trampoline (not original caller!)
2. Trampoline triggers INT3
3. Kernel handler runs BPF program (logs exit, duration)
4. Restores original return address
5. Jumps to real caller
```

**Stack Manipulation:**
```
Normal function call:
┌──────────────┐
│ caller addr  │ ← rsp (return address)
├──────────────┤
│ saved %rbp   │
├──────────────┤
│ local vars   │
└──────────────┘

With uretprobe:
┌──────────────┐
│ trampoline   │ ← rsp (modified return address!)
├──────────────┤
│ saved %rbp   │
├──────────────┤
│ local vars   │
└──────────────┘

Kernel remembers:
original_return[context] = caller_addr
```

## Method 3: strace - System Call Tracing

### How strace Works

**Step 1: ptrace Attach**
```c
// strace command line: strace -e ioctl python inference.py

// strace process does:
pid = fork();
if (pid == 0) {
    // Child process
    ptrace(PTRACE_TRACEME, 0, NULL, NULL);  // Allow parent to trace me
    exec("python", ["inference.py"]);
} else {
    // Parent process (strace)
    wait(&status);  // Wait for child to exec

    // Attach to child
    ptrace(PTRACE_SETOPTIONS, pid, NULL, PTRACE_O_TRACESYSGOOD);

    // Main loop
    while (1) {
        ptrace(PTRACE_SYSCALL, pid, NULL, NULL);  // Continue until next syscall
        wait(&status);  // Wait for syscall

        // Read registers to get syscall info
        struct user_regs_struct regs;
        ptrace(PTRACE_GETREGS, pid, NULL, &regs);

        // Decode syscall
        if (regs.orig_rax == __NR_ioctl) {
            printf("ioctl(fd=%ld, cmd=%lx, ...)\n", regs.rdi, regs.rsi);
        }

        // Continue to syscall exit
        ptrace(PTRACE_SYSCALL, pid, NULL, NULL);
        wait(&status);
    }
}
```

**Step 2: Syscall Interception**

When traced process makes syscall:

```
User Process:
  cuLaunchKernel() in libcuda.so
    ↓
  syscall(ioctl, fd, cmd, args)
    ↓
  [KERNEL TRAP]
    ↓
Kernel:
  - Sees PTRACE_SYSCALL active
  - Stops process
  - Sends SIGTRAP to tracer (strace)
    ↓
strace process:
  - Wakes up from wait()
  - Reads registers (fd, cmd, args)
  - Prints: ioctl(3, 0xc0044601, ...)
  - Continues child process
    ↓
Kernel:
  - Actually executes ioctl()
  - Returns result
    ↓
  - Stops again (syscall exit)
  - Sends SIGTRAP to tracer
    ↓
strace process:
  - Reads return value
  - Prints: = 0
```

## Data Flow: From Hook to Visualization

### Complete Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: Data Collection (Runtime)                         │
└─────────────────────────────────────────────────────────────┘
  Your Program → CUDA Call → Hook Intercepts
                                ↓
                           Writes JSON line
                                ↓
                        cuda_trace.jsonl
  {"ts":0.001234,"op_id":1,"phase":"B","name":"cuMemAlloc"}
  {"ts":0.001890,"op_id":1,"phase":"E","name":"cuMemAlloc"}

┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: Parsing (visualize_pipeline.py)                   │
└─────────────────────────────────────────────────────────────┘
  Read JSONL file
    ↓
  Parse each line → CUDATraceEvent object
    ↓
  Match Begin/End events by op_id
    ↓
  Create Operation objects with:
    - name, start, end, duration, depth

┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: Analysis                                          │
└─────────────────────────────────────────────────────────────┘
  Group by category:
    memory_mgmt: [op1, op2]
    transfer: [op3, op4, op5]
    kernel: [op6]
    ↓
  Calculate statistics:
    total_time = Σ durations
    percentage = category_time / total_time

┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: Visualization                                     │
└─────────────────────────────────────────────────────────────┘
  ASCII Timeline:
    Map timestamps to X positions
    Group by depth (Y axis)
    Draw with category symbols

  Chrome Trace:
    Convert to Chrome Trace Event Format
    {name, ts, ph: 'B'/'E', pid, tid}
```

## Performance Impact

### LD_PRELOAD Overhead

```
Normal call:
  Application → libcuda.so → ioctl → GPU
  Latency: ~10 μs

With LD_PRELOAD:
  Application → hook → log (2 μs) → libcuda.so → ioctl → GPU
  Latency: ~12 μs

Overhead: ~20% for fast operations, <1% for GPU operations (ms scale)
```

### eBPF Overhead

```
Normal call:
  Application → libcuda.so function
  Latency: nanoseconds

With uprobe:
  Application → INT3 trap → kernel (1-2 μs) → BPF VM → return
  Latency: ~2-5 μs

Overhead: Higher per-call, but doesn't modify application memory
```

### Why This Matters

The traces reveal:
1. **Exact timing** of every CUDA operation
2. **Call hierarchy** (depth tracking)
3. **Bottlenecks** (where time is spent)
4. **Scheduling opportunities** (gaps = idle GPU)
5. **Memory patterns** (allocations, transfers)

For Little Boy, this shows exactly where and how to virtualize!
