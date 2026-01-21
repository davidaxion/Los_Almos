# GPU Inference Research Materials

Advanced research on GPU operations, CUDA internals, and inference optimization techniques.

## 📚 Research Areas

### 1. CUDA Hooking (`cuda-hooking/`)
**Understanding GPU operations at the CUDA level**

Learn how to intercept and trace CUDA API calls to understand:
- Memory allocation patterns
- Kernel launches
- Data transfers (Host ↔ Device)
- GPU utilization patterns

**Why this matters for learning:**
- See exactly what your code does on the GPU
- Debug performance issues
- Understand memory management
- Profile GPU usage

**Key Documents:**
- [`cuda-hooking/README.md`](cuda-hooking/README.md) - Overview and getting started
- [`cuda-hooking/notes/hooking-approach.md`](cuda-hooking/notes/hooking-approach.md) - Technical deep dive
- [`cuda-hooking/notes/getting-started.md`](cuda-hooking/notes/getting-started.md) - Quick start guide

**Applies to Modules:**
- Module 1: Basic GPU (understand your first GPU operations)
- Module 4: NVIDIA Benchmarking (profile performance)

---

### 2. libcuda Hooking (`libcuda-hooking/`)
**Low-level GPU driver interception**

Advanced techniques for intercepting calls to the NVIDIA driver:
- Driver-level tracing
- Performance profiling
- Resource tracking
- Custom GPU schedulers

**Why this matters:**
- Deep understanding of GPU architecture
- Performance optimization insights
- Advanced debugging techniques
- Build custom GPU tools

**Key Documents:**
- [`libcuda-hooking/README.md`](libcuda-hooking/README.md) - Main documentation
- [`libcuda-hooking/notes/how-hooking-works.md`](libcuda-hooking/notes/how-hooking-works.md) - Technical explanation
- [`libcuda-hooking/notes/tracing-mechanics.md`](libcuda-hooking/notes/tracing-mechanics.md) - Tracing internals
- [`libcuda-hooking/QUICK_START.md`](libcuda-hooking/QUICK_START.md) - Get started quickly

**Advanced Topics:**
- [`libcuda-hooking/ebpf/`](libcuda-hooking/ebpf/) - eBPF kernel-level hooking
- [`libcuda-hooking/test/`](libcuda-hooking/test/) - Test frameworks

**Applies to Modules:**
- Module 3: Parallel Computing (understand multi-GPU communication)
- Module 4: NVIDIA Benchmarking (advanced profiling)

---

### 3. K3s vLLM Tracing (`k3s-vllm-tracing/`)
**Production inference monitoring**

Real-world tracing of vLLM inference in Kubernetes:
- Request flow tracking
- KV-cache behavior
- Memory patterns during inference
- Multi-request scheduling

**Why this matters:**
- Understand production inference systems
- Optimize vLLM deployments
- Debug performance issues
- Plan capacity

**Key Documents:**
- [`k3s-vllm-tracing/README.md`](k3s-vllm-tracing/README.md) - Project overview
- [`k3s-vllm-tracing/docs/ARCHITECTURE.md`](k3s-vllm-tracing/docs/ARCHITECTURE.md) - System architecture

**Applies to Modules:**
- Module 1: Basic GPU (understand vLLM behavior)
- Module 2: SLURM Cluster (production deployment patterns)

---

## 🎓 How to Use These Materials

### For Beginners (Module 1)

Start with practical examples:
1. Run Module 1 exercises first
2. Then read [`cuda-hooking/notes/getting-started.md`](cuda-hooking/notes/getting-started.md)
3. Try tracing your own code from exercises
4. Understand what happens when you call `.cuda()`

### For Intermediate (Modules 2 & 4)

Connect theory to practice:
1. Complete SLURM or Benchmarking modules
2. Read [`libcuda-hooking/notes/how-hooking-works.md`](libcuda-hooking/notes/how-hooking-works.md)
3. Profile your SLURM jobs
4. Analyze vLLM behavior with tracing tools

### For Advanced (Module 3)

Deep technical understanding:
1. Implement parallel computing patterns
2. Study [`libcuda-hooking/ebpf/`](libcuda-hooking/ebpf/) - kernel-level hooks
3. Trace NCCL communication
4. Build custom profiling tools

---

## 🛠️ Practical Integration

### Trace Your GPU Code

Add tracing to any Module 1 exercise:

```bash
# 1. Set up LD_PRELOAD hooking
export LD_PRELOAD=/path/to/cuda-hook.so

# 2. Run your code
python3 ~/exercises/01-hello-gpu.py

# 3. Analyze trace output
cat /tmp/cuda-trace.log
```

### Profile vLLM Inference

```bash
# 1. Run vLLM with tracing
LD_PRELOAD=/path/to/libcuda-hook.so \
  python3 ~/exercises/02-vllm-inference.py

# 2. Analyze memory patterns
grep "cuMemAlloc" /tmp/cuda-trace.log

# 3. Find kernel launches
grep "cuLaunchKernel" /tmp/cuda-trace.log
```

### Monitor Multi-GPU Communication

```bash
# Trace NCCL in Module 3
export NCCL_DEBUG=INFO
export LD_PRELOAD=/path/to/nccl-hook.so

python3 distributed_train.py
```

---

## 📖 Learning Path

### Path 1: Understanding GPU Basics
1. Module 1: Basic GPU Setup
2. Read: `cuda-hooking/notes/getting-started.md`
3. Exercise: Trace `01-hello-gpu.py`
4. Understand: What `.cuda()` actually does

### Path 2: Inference Optimization
1. Module 1: Basic GPU Setup
2. Read: `k3s-vllm-tracing/README.md`
3. Module 4: NVIDIA Benchmarking
4. Exercise: Profile vLLM with different batch sizes

### Path 3: Advanced GPU Programming
1. Module 3: Parallel Computing
2. Read: `libcuda-hooking/README.md`
3. Read: `libcuda-hooking/ebpf/README.md`
4. Exercise: Build custom GPU profiler

---

## 🔬 Research Projects

### Project 1: Build a GPU Profiler
**Goal**: Create a tool to profile GPU memory usage

**Steps:**
1. Study `libcuda-hooking/notes/how-hooking-works.md`
2. Implement LD_PRELOAD hook for `cuMemAlloc`
3. Log all allocations with timestamps
4. Visualize memory usage over time

### Project 2: Trace Inference Pipeline
**Goal**: Understand complete inference flow

**Steps:**
1. Run `02-vllm-inference.py` with tracing
2. Map CUDA calls to vLLM operations
3. Identify bottlenecks
4. Document findings

### Project 3: Multi-GPU Communication Analysis
**Goal**: Understand NCCL all-reduce patterns

**Steps:**
1. Set up Module 3 parallel environment
2. Implement AllReduce with eBPF tracing
3. Measure communication overhead
4. Optimize based on findings

---

## 📊 Research Data

These materials include:
- **Working code examples** for CUDA hooking
- **Real-world traces** from production systems
- **Performance data** from benchmarks
- **Architecture diagrams** explaining GPU flow

Use them to:
- Understand your exercises better
- Debug performance issues
- Build custom tools
- Contribute back to research

---

## 🤝 Contributing

Found interesting GPU behavior? Document it!

```bash
# Create new research directory
mkdir -p shared/research/my-research

# Document your findings
echo "# My GPU Research" > shared/research/my-research/README.md

# Share with the community
git add shared/research/my-research
git commit -m "Add research on [topic]"
```

---

## 🔗 External Resources

### NVIDIA Documentation
- [CUDA C Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [CUDA Runtime API](https://docs.nvidia.com/cuda/cuda-runtime-api/)
- [CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/)

### Tools
- [NVIDIA Nsight Systems](https://developer.nvidia.com/nsight-systems)
- [NVIDIA Nsight Compute](https://developer.nvidia.com/nsight-compute)
- [nvprof](https://docs.nvidia.com/cuda/profiler-users-guide/)

### Community
- [NVIDIA Developer Forums](https://forums.developer.nvidia.com/)
- [r/CUDA](https://reddit.com/r/CUDA)
- [GPU Programming Discord](https://discord.gg/gpu)

---

## 🎯 Quick Links by Module

| Module | Relevant Research | Why |
|--------|------------------|-----|
| Module 1: Basic GPU | `cuda-hooking/notes/getting-started.md` | Understand first GPU operations |
| Module 2: SLURM | `k3s-vllm-tracing/` | Production deployment patterns |
| Module 3: Parallel | `libcuda-hooking/ebpf/` | Multi-GPU communication |
| Module 4: Benchmarking | `libcuda-hooking/notes/tracing-mechanics.md` | Advanced profiling |

---

**Ready to dive deep?** Start with your module, then explore the research materials! 🔬
