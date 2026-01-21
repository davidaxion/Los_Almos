# Running CUDA Inference Trace Test

Complete guide to tracing the full inference pipeline from weights loading to response generation.

## ⚠️ Prerequisites

### System Requirements

**IMPORTANT:** eBPF tracing requires **Linux** with:
- NVIDIA GPU + drivers
- Kernel 4.9+ (5.x+ recommended)
- Root access (sudo)

**Current System:** macOS (detected)
- You'll need to run this on a Linux machine with NVIDIA GPU
- Consider: AWS EC2 g4dn/g5 instances, Lambda Labs, or local Linux box

### Software Requirements

```bash
# On your Linux machine with NVIDIA GPU:

# 1. Install CUDA and PyTorch
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# 2. Install transformers (for realistic test)
pip install transformers

# 3. Install eBPF tools
sudo apt update
sudo apt install -y bpftrace linux-headers-$(uname -r)

# 4. Verify installations
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"
sudo bpftrace --version
```

## 🚀 Quick Start

### Test 1: Simple Inference (Recommended First)

```bash
cd /path/to/LittleBoy/research/libcuda-hooking/test

# Run WITHOUT tracing (verify it works)
python simple_inference.py

# Run WITH eBPF tracing
sudo ../ebpf/run_trace.sh python simple_inference.py
```

**Expected output:**
```
=== CUDA Inference Pipeline Test ===

[1] Checking CUDA availability...
✓ CUDA available: NVIDIA GeForce RTX 3090
  Memory: 24.00 GB

[2] Initializing CUDA context...
✓ CUDA initialized (0.234s)

[3] Loading model weights to GPU...
✓ Model loaded to GPU (0.156s)
  Parameters: 1,837,568 (7.02 MB)

[4] Preparing input data...
✓ Input data transferred to GPU (0.003s)
  Batch size: 32
  Input shape: torch.Size([32, 512])

[5] Warmup run (compiles kernels)...
✓ Warmup complete (0.089s)

[6] Running inference...
  Iteration 1/10: 2.345 ms
  Iteration 2/10: 1.234 ms
  ...

✓ Inference complete
  Average time: 1.456 ms
  Throughput: 21978.02 samples/sec

[7] Retrieving results from GPU...
✓ Results transferred to CPU (0.001s)

[8] GPU Memory Statistics...
  Allocated: 7.23 MB
  Reserved: 20.00 MB

[9] Cleaning up...
✓ GPU memory freed
```

**Trace output location:**
```
traces/trace_<timestamp>.jsonl
```

### Test 2: Transformer Inference (Realistic)

```bash
# Run WITHOUT tracing (takes longer - downloads model)
python transformer_inference.py

# Run WITH eBPF tracing
sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py

# Custom model and prompt
python transformer_inference.py --model gpt2 --prompt "Once upon a time"
```

**Expected output:**
```
=== TRANSFORMER INFERENCE PIPELINE TEST ===

[Stage 1] CUDA Initialization
Device: NVIDIA GeForce RTX 3090
Memory: 24.00 GB

[Stage 2] Loading Tokenizer
✓ Tokenizer loaded: gpt2
✓ Time: 0.234s

[Stage 3] Loading Model Weights to GPU
✓ Model loaded: gpt2
  Parameters: 124,439,808 (0.23 GB)
  Time: 2.345s
  GPU Memory: 0.25 GB

[Stage 4] Tokenizing Input (Prompt Processing)
Prompt: "Hello, how are you?"
✓ Tokenized: 6 tokens
  Token IDs: [15496, 11, 703, 389, 345, 30]...
  Time: 0.012s

[Stage 5] Warmup Inference (Kernel Compilation)
✓ Warmup complete: 0.456s

[Stage 6] Running Inference (Text Generation)
Generating response (20 tokens)...

✓ Inference complete: 1.234s
  Tokens generated: 20
  Tokens/second: 16.21

[Stage 7] Decoding Response (Output Processing)
✓ Decoding complete: 0.003s

RESPONSE:
--------------------------------------------------------------------------------
Hello, how are you? I'm doing great! I just finished a long day at work and...
--------------------------------------------------------------------------------
```

## 📊 Analyzing Results

### View Trace Summary

```bash
# After tracing completes, check output:
ls -lh traces/

# View trace summary
tail -50 traces/trace_*.jsonl
```

### Extract Statistics

```bash
# Count events by type
cat traces/trace_*.jsonl | grep -E '^{' | jq -r '.type' | sort | uniq -c

# Find all unique CUDA functions called
cat traces/trace_*.jsonl | grep -E '^{' | jq -r '.name' | sort | uniq

# Count memory allocations
cat traces/trace_*.jsonl | grep -E '^{' | jq 'select(.type=="memory")' | wc -l

# Count kernel launches
cat traces/trace_*.jsonl | grep -E '^{' | jq 'select(.type=="kernel" and .op=="launch")' | wc -l
```

### Visualize Pipeline

```bash
# Generate ASCII timeline
python ../tools/visualize_pipeline.py traces/trace_*.jsonl

# Generate Chrome trace (interactive)
python ../tools/visualize_pipeline.py --format=chrome traces/trace_*.jsonl

# Open in Chrome
# 1. Open Chrome browser
# 2. Navigate to: chrome://tracing
# 3. Click "Load" and select trace.json
```

## 🔍 What You'll See in the Trace

### Simple Inference Test

**CUDA Functions Traced:**

1. **Initialization (Stage 1-2)**
   ```
   cuInit
   cuDeviceGet
   cuDeviceGetAttribute (multiple)
   cuCtxCreate
   ```

2. **Model Loading (Stage 3)**
   ```
   cuMemAlloc (one per model parameter tensor)
   cuMemcpyHtoD (transfer weights to GPU)
   ```

3. **Input Preparation (Stage 4)**
   ```
   cuMemAlloc (input buffer)
   cuMemcpyHtoD (transfer input data)
   ```

4. **Inference Execution (Stage 5-6)**
   ```
   cuLaunchKernel (matrix multiply)
   cuLaunchKernel (activation - ReLU)
   cuLaunchKernel (matrix multiply)
   ... (repeated per layer)
   cuStreamSynchronize (wait for completion)
   ```

5. **Result Retrieval (Stage 7)**
   ```
   cuMemcpyDtoH (transfer output)
   ```

6. **Cleanup (Stage 9)**
   ```
   cuMemFree (free all allocations)
   ```

### Transformer Inference Test

**Additional CUDA Activity:**

1. **Model Loading** - Much more extensive
   - ~500-1000 cuMemAlloc calls (one per parameter tensor)
   - Large cuMemcpyHtoD transfers (gigabytes of weights)

2. **Per-Token Generation Loop** (repeated 20 times)
   ```
   For each token:
     cuLaunchKernel (embedding lookup)
     For each transformer layer (12 layers in GPT-2):
       cuLaunchKernel (attention Q, K, V projections)
       cuLaunchKernel (attention scores)
       cuLaunchKernel (softmax)
       cuLaunchKernel (attention output)
       cuLaunchKernel (FFN layer 1)
       cuLaunchKernel (GELU activation)
       cuLaunchKernel (FFN layer 2)
     cuLaunchKernel (final layer norm)
     cuLaunchKernel (logits calculation)
     cuLaunchKernel (sampling/argmax)
     cuStreamSynchronize
   ```

**Expected counts:**
- cuMemAlloc: ~500-1000 (model parameters)
- cuLaunchKernel: ~600-800 (per-token: ~30-40 × 20 tokens)
- cuMemcpy: ~20-30 (input/output transfers)

## 📈 Expected Timing Breakdown

### Simple Inference

```
Category          Time      % Total
-----------------------------------
Initialization    0.234s    15%
Weight Loading    0.156s    10%
Input Transfer    0.003s    0.2%
Kernel Compile    0.089s    6%
Inference         0.015s    1%
Sync              0.012s    0.8%
Output Transfer   0.001s    0.1%
Total            ~0.51s
```

### Transformer Inference (GPT-2)

```
Category          Time      % Total
-----------------------------------
Initialization    0.3s      8%
Weight Loading    2.3s      60%
Input Transfer    0.01s     0.3%
Warmup            0.5s      13%
Inference         1.2s      31%
  - Per token    ~60ms
Output Transfer   0.003s    0.1%
Total            ~3.8s
```

**Insights:**
- Weight loading dominates startup time (60%)
- Per-token inference is consistent (~60ms each)
- I/O (transfers) is minimal (<1%)
- Most time is compute-bound (good!)

## 🔬 Pipeline Analysis for Little Boy

### Key Observations to Find

1. **Context Switch Points**
   ```bash
   # Look for gaps in execution
   cat traces/trace_*.jsonl | grep -E '^{' | \
     jq 'select(.name=="cuLaunchKernel")' | \
     jq -r '.ts' | \
     awk 'NR>1 {print $1-prev} {prev=$1}'
   ```

2. **Memory Allocation Patterns**
   ```bash
   # When and how much memory is allocated
   cat traces/trace_*.jsonl | grep -E '^{' | \
     jq 'select(.type=="memory" and .op=="alloc")' | \
     jq '{ts, size}'
   ```

3. **GPU Idle Time**
   ```bash
   # Time between sync and next kernel launch
   # These are virtualization opportunities!
   ```

4. **Kernel-Level Activity** (with --kernel flag)
   ```bash
   # IOCTL calls to nvidia.ko
   cat traces/trace_*.jsonl | grep -E '^{' | \
     jq 'select(.type=="kernel")' | \
     jq '{ts, name}'
   ```

## 🐛 Troubleshooting

### Test Runs But No Trace File

```bash
# Check sudo privileges
sudo whoami  # Should print "root"

# Check bpftrace is working
sudo bpftrace -l 'kprobe:*' | wc -l  # Should show thousands of probes

# Run with verbose output
sudo bpftrace trace_cuda_full.bt 2>&1 | tee debug.log
```

### CUDA Not Available

```bash
# Check NVIDIA driver
nvidia-smi

# Check CUDA installation
nvcc --version

# Check PyTorch CUDA
python -c "import torch; print(torch.cuda.is_available())"
```

### eBPF Errors

```bash
# Update kernel headers
sudo apt install linux-headers-$(uname -r)

# Check kernel version (need 4.9+)
uname -r

# Try simpler probe
sudo bpftrace -e 'BEGIN { printf("Hello\n"); exit(); }'
```

### Out of Memory

```bash
# For large models, use smaller batch size or FP16
python transformer_inference.py --model distilgpt2  # Smaller model

# Or limit trace to specific functions
sudo bpftrace -e '
  uprobe:/lib/*/libcuda.so:cuLaunchKernel,
  uprobe:/lib/*/libcuda.so:cuMemAlloc {
    printf("%s\n", probe);
  }
'
```

## 📝 Next Steps After Testing

1. **Analyze the traces** - Look for patterns
   ```bash
   python ../tools/visualize_pipeline.py --format=all traces/trace_*.jsonl
   ```

2. **Identify bottlenecks** - Where is time spent?
   ```bash
   cat traces/trace_*.jsonl | grep -E '^{' | \
     jq 'select(.duration_us) | {name, duration_us}' | \
     jq -s 'group_by(.name) | map({name: .[0].name, total: map(.duration_us) | add})'
   ```

3. **Find scheduling opportunities** - GPU idle periods
   - Gaps between kernel launches
   - Sync wait times
   - Context switch overhead

4. **Correlate with kernel activity** (if --kernel used)
   - How do CUDA calls map to IOCTLs?
   - What does scheduler do?
   - When are contexts switched?

5. **Design Little Boy hooks** based on findings
   - Where to intercept for virtualization
   - How to multiplex workloads
   - Overhead estimates

## 📚 Example Analysis Workflow

```bash
# 1. Run trace
sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py

# 2. Get summary statistics
cat traces/trace_*.jsonl | grep '^{' | \
  jq -s 'group_by(.type) | map({type: .[0].type, count: length})'

# 3. Find slowest operations
cat traces/trace_*.jsonl | grep '^{' | \
  jq 'select(.duration_us) | {name, duration_us}' | \
  jq -s 'sort_by(.duration_us) | reverse | .[0:10]'

# 4. Generate visualization
python ../tools/visualize_pipeline.py --format=chrome traces/trace_*.jsonl

# 5. Open in Chrome
google-chrome trace.json  # Or: chrome://tracing
```

## 🎯 Success Criteria

You've successfully traced the pipeline when you can answer:

- ✅ How many CUDA calls are made during model loading?
- ✅ How many kernels are launched per inference iteration?
- ✅ What is the ratio of compute time vs I/O time?
- ✅ Where are the GPU idle periods?
- ✅ How much time is spent in cuStreamSynchronize? (blocking)
- ✅ What IOCTL commands are sent to nvidia.ko?
- ✅ When does the GPU scheduler get invoked?

## 📖 Further Reading

- `../ebpf/README.md` - eBPF tracing overview
- `../ebpf/KERNEL_HOOKS.md` - Adding kernel-level hooks
- `../notes/tracing-mechanics.md` - How tracing works
- `../tools/visualize_pipeline.py --help` - Visualization options
