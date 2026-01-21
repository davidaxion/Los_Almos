# CUDA Inference Pipeline Tests

Test scripts for tracing complete inference workflows from model loading to response generation.

## ⚠️ Important Note

**Current System: macOS**

eBPF tracing **only works on Linux**. To run these tests with full tracing:

1. Move to a Linux system with NVIDIA GPU, OR
2. Use cloud instance: AWS g4dn/g5, Lambda Labs, etc.

You can still run the tests WITHOUT tracing on macOS (if you have CUDA installed), but you won't get the eBPF trace data.

## 🚀 Quick Start (Linux + NVIDIA GPU)

```bash
# Simple test
sudo ../ebpf/run_trace.sh python simple_inference.py

# Realistic transformer test
sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py
```

## 📁 Files

| File | Description |
|------|-------------|
| `simple_inference.py` | Simple MLP inference test - fast, good for testing setup |
| `transformer_inference.py` | Realistic GPT-2 inference - shows real workload patterns |
| `RUN_TEST.md` | Complete guide with analysis workflows |
| `README.md` | This file |

## 🎯 What Gets Traced

### Complete Pipeline

```
1. CUDA Initialization
   └─> cuInit, cuDeviceGet, cuCtxCreate

2. Model Weight Loading
   └─> cuMemAlloc (hundreds of calls)
   └─> cuMemcpyHtoD (GB of data)

3. Input Preparation
   └─> cuMemAlloc (input buffers)
   └─> cuMemcpyHtoD (prompt data)

4. Inference Execution
   └─> cuLaunchKernel (matrix ops)
   └─> cuLaunchKernel (activations)
   └─> cuStreamSynchronize (wait for GPU)

5. Output Retrieval
   └─> cuMemcpyDtoH (results back to CPU)

6. Cleanup
   └─> cuMemFree (release memory)
```

### With Kernel Hooks (--kernel flag)

Also traces:
- `nvidia_ioctl` - Userspace → kernel communication
- `nv_schedule_work` - GPU work scheduling
- `nv_mem_alloc` - Kernel-level memory allocation

## 📊 Example Output

### Simple Test
```bash
$ sudo ../ebpf/run_trace.sh python simple_inference.py

=== CUDA Inference Pipeline Test ===

[1] Checking CUDA availability...
✓ CUDA available: NVIDIA GeForce RTX 3090

[2] Initializing CUDA context...
✓ CUDA initialized (0.234s)

[3] Loading model weights to GPU...
✓ Model loaded to GPU (0.156s)
  Parameters: 1,837,568 (7.02 MB)

[6] Running inference...
  Iteration 1/10: 2.345 ms
  Average time: 1.456 ms
  Throughput: 21978.02 samples/sec

=== Trace saved to: traces/trace_20260121_153045.jsonl ===
```

### Transformer Test
```bash
$ sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py

[Stage 3] Loading Model Weights to GPU
✓ Model loaded: gpt2
  Parameters: 124,439,808 (0.23 GB)
  GPU Memory: 0.25 GB

[Stage 6] Running Inference (Text Generation)
✓ Inference complete: 1.234s
  Tokens generated: 20
  Tokens/second: 16.21

RESPONSE:
Hello, how are you? I'm doing great! I just finished...
```

## 📈 Analyzing Results

```bash
# View summary
tail -30 traces/trace_*.jsonl

# Count CUDA function calls
cat traces/trace_*.jsonl | grep '^{' | jq -r '.name' | sort | uniq -c

# Visualize timeline
python ../tools/visualize_pipeline.py traces/trace_*.jsonl

# Generate Chrome trace (interactive)
python ../tools/visualize_pipeline.py --format=chrome traces/trace_*.jsonl
# Open trace.json in chrome://tracing
```

## 🔧 Setup Requirements

### Linux System
```bash
# Install dependencies
sudo apt install -y bpftrace linux-headers-$(uname -r)
pip install torch transformers

# Verify
sudo bpftrace --version
python -c "import torch; print(torch.cuda.is_available())"
```

### macOS (Limited - No eBPF)
```bash
# Can run tests but not trace them
pip install torch transformers

# Run without tracing
python simple_inference.py
python transformer_inference.py
```

## 🎓 Learning Objectives

By running these tests, you'll discover:

1. **Memory Patterns** - How much VRAM is needed, when it's allocated
2. **Kernel Launch Patterns** - Which operations dominate GPU time
3. **I/O Bottlenecks** - CPU↔GPU transfer overhead
4. **Scheduling Behavior** - GPU idle periods, context switches
5. **Layer-by-Layer Timing** - Where inference time is spent

## 🔬 For Little Boy Research

These traces help you:

- **Find virtualization points** - Where to intercept for multiplexing
- **Measure overhead** - Cost of context switching
- **Identify idle periods** - When GPU can run other workloads
- **Understand scheduling** - How driver queues work to GPU

## 📚 Documentation

- **[RUN_TEST.md](RUN_TEST.md)** - Complete testing guide
- **[../ebpf/README.md](../ebpf/README.md)** - eBPF tracing overview
- **[../ebpf/KERNEL_HOOKS.md](../ebpf/KERNEL_HOOKS.md)** - Kernel-level hooks

## 🐛 Common Issues

### "CUDA not available"
```bash
# Check driver
nvidia-smi

# Check PyTorch installation
python -c "import torch; print(torch.version.cuda)"
```

### "Permission denied" (eBPF)
```bash
# Must use sudo
sudo ../ebpf/run_trace.sh python test.py
```

### "transformers not found"
```bash
# Install transformers
pip install transformers

# Or run simple test instead
python simple_inference.py
```

## 🎯 Quick Commands

```bash
# Test 1: Simple (recommended first)
sudo ../ebpf/run_trace.sh python simple_inference.py

# Test 2: Transformer
sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py

# Analyze results
python ../tools/visualize_pipeline.py traces/trace_*.jsonl

# View in Chrome
python ../tools/visualize_pipeline.py --format=chrome traces/trace_*.jsonl
# Open chrome://tracing and load trace.json
```

## ✅ Success Checklist

- [ ] Tests run successfully without tracing
- [ ] eBPF tracing captures events (Linux only)
- [ ] Trace file generated in `traces/`
- [ ] Can visualize pipeline
- [ ] Understand memory allocation patterns
- [ ] Identify kernel launch patterns
- [ ] See kernel-level activity (with --kernel)

Read [RUN_TEST.md](RUN_TEST.md) for detailed guide!
