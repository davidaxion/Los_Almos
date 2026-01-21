# Module 4: NVIDIA Benchmarking

**Difficulty**: ⭐⭐ Intermediate
**Time**: 1-2 hours
**Cost**: Variable (~$0.50-$3.00/hour depending on GPU)
**Prerequisites**: Module 1 completed, basic understanding of performance metrics

## 🎯 Learning Objectives

By the end of this module, you will:
- ✅ Compare different NVIDIA GPU architectures (T4, L4, A10G, V100, A100)
- ✅ Benchmark inference performance across GPU types
- ✅ Measure throughput (tokens/second) for different models
- ✅ Analyze GPU utilization and bottlenecks
- ✅ Calculate performance per dollar metrics
- ✅ Make informed decisions about GPU selection
- ✅ Optimize vLLM configurations for each GPU

## 📚 What You'll Build

A comprehensive benchmarking framework with:
- Automated GPU performance testing
- vLLM inference benchmarks
- Multi-model comparison scripts
- Performance visualization tools
- Cost analysis spreadsheets
- Configuration optimization guides

## 🚀 Quick Start

```bash
# 1. Deploy a GPU instance
./deploy.sh

# 2. SSH into instance
ssh -i ~/.ssh/id_rsa ubuntu@<INSTANCE_IP>

# 3. Run benchmarks
cd ~/benchmarks
./run_all_benchmarks.sh

# 4. View results
cat results/benchmark_summary.txt
```

## 📖 Concepts Covered

### 1. NVIDIA GPU Comparison

**GPU Architectures:**

| GPU | Architecture | Year | CUDA Cores | Tensor Cores | VRAM | TDP | Typical Use |
|-----|-------------|------|------------|--------------|------|-----|-------------|
| T4 | Turing | 2018 | 2,560 | 320 | 16GB | 70W | Inference, small models |
| L4 | Ada Lovelace | 2023 | 7,424 | 232 | 24GB | 72W | Inference, 70B models |
| A10G | Ampere | 2020 | 9,216 | 288 | 24GB | 150W | Training, inference |
| V100 | Volta | 2017 | 5,120 | 640 | 16GB | 300W | Training, large models |
| A100 | Ampere | 2020 | 6,912 | 432 | 40GB | 400W | Large model training |

**Key Differences:**
- **Tensor Cores**: Specialized for matrix operations (crucial for transformers)
- **VRAM**: Determines max model size
- **TDP (Thermal Design Power)**: Power consumption / heat generation
- **Architecture**: Newer = better efficiency

### 2. Performance Metrics

**Throughput Metrics:**
- **Tokens/second**: For text generation
- **Samples/second**: For batch inference
- **TFLOPS**: Theoretical compute capacity
- **Memory Bandwidth**: Data transfer speed

**Efficiency Metrics:**
- **Performance per Watt**: Tokens/second per Watt
- **Performance per Dollar**: Tokens/second per $/hour
- **GPU Utilization**: % of GPU capacity used
- **Memory Utilization**: % of VRAM used

### 3. Benchmarking Methodology

```
┌─────────────────────────────────────────┐
│        Benchmarking Workflow            │
│                                         │
│  1. Select GPU Type                     │
│          ↓                              │
│  2. Deploy Instance                     │
│          ↓                              │
│  3. Install Dependencies                │
│          ↓                              │
│  4. Run Standardized Tests              │
│     - Model Loading Time                │
│     - Single Request Latency            │
│     - Throughput (various batch sizes)  │
│     - Memory Usage                      │
│     - Power Consumption                 │
│          ↓                              │
│  5. Record Results                      │
│          ↓                              │
│  6. Calculate Metrics                   │
│     - Tokens/sec                        │
│     - Cost per 1M tokens                │
│     - Performance/$ ratio               │
│          ↓                              │
│  7. Compare Against Baseline            │
│          ↓                              │
│  8. Optimize Configuration              │
│          ↓                              │
│  9. Re-test and Validate                │
└─────────────────────────────────────────┘
```

### 4. vLLM Configuration Impact

**Key vLLM Parameters:**
```python
llm = LLM(
    model="meta-llama/Llama-2-7b-hf",
    gpu_memory_utilization=0.9,   # How much VRAM to use
    max_num_batched_tokens=8192,  # Max tokens in batch
    max_num_seqs=256,             # Max concurrent requests
    tensor_parallel_size=1,       # GPUs for tensor parallelism
    dtype="float16",              # Precision (float16/bfloat16)
)
```

**Impact on Performance:**
- `gpu_memory_utilization`: Higher = more KV cache = better throughput
- `max_num_batched_tokens`: Larger batches = better throughput, higher latency
- `dtype`: float16 vs bfloat16 vs int8 - accuracy vs speed tradeoff

## 🛠️ Exercises

### Exercise 1: Basic GPU Benchmark

**File**: `benchmarks/gpu_specs.py`

```python
#!/usr/bin/env python3
import torch
import subprocess
import json

def get_gpu_specs():
    """Get comprehensive GPU specifications"""

    if not torch.cuda.is_available():
        print("❌ No GPU available")
        return

    device = torch.cuda.current_device()
    props = torch.cuda.get_device_properties(device)

    specs = {
        "name": torch.cuda.get_device_name(device),
        "compute_capability": f"{props.major}.{props.minor}",
        "total_memory_gb": props.total_memory / 1e9,
        "sm_count": props.multi_processor_count,
        "cuda_cores": "Unknown",  # Varies by architecture
        "memory_clock_mhz": props.memory_clock_rate / 1000,
        "memory_bandwidth_gb_s": (props.memory_clock_rate * props.memory_bus_width * 2) / 8 / 1e6
    }

    # Get additional info from nvidia-smi
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,driver_version,pstate,temperature.gpu,power.draw,power.limit",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True
        )
        nvidia_info = result.stdout.strip().split(", ")
        specs["driver_version"] = nvidia_info[1]
        specs["power_state"] = nvidia_info[2]
        specs["temperature_c"] = nvidia_info[3]
        specs["power_draw_w"] = nvidia_info[4]
        specs["power_limit_w"] = nvidia_info[5]
    except:
        pass

    # Print specs
    print("=" * 70)
    print("GPU Specifications")
    print("=" * 70)
    for key, value in specs.items():
        print(f"{key:25}: {value}")
    print("=" * 70)

    return specs

if __name__ == "__main__":
    get_gpu_specs()
```

**Learning goals:**
- Read GPU specifications
- Understand hardware capabilities
- Compare theoretical vs actual performance

---

### Exercise 2: TFLOPS Benchmark

**File**: `benchmarks/tflops_benchmark.py`

```python
#!/usr/bin/env python3
import torch
import time

def benchmark_matmul(size=8192, iterations=100):
    """Benchmark matrix multiplication to estimate TFLOPS"""

    device = torch.device('cuda')

    # Create random matrices
    A = torch.randn(size, size, dtype=torch.float16, device=device)
    B = torch.randn(size, size, dtype=torch.float16, device=device)

    # Warm up
    for _ in range(10):
        C = torch.matmul(A, B)
    torch.cuda.synchronize()

    # Benchmark
    start = time.time()
    for _ in range(iterations):
        C = torch.matmul(A, B)
    torch.cuda.synchronize()
    elapsed = time.time() - start

    # Calculate TFLOPS
    # Matrix multiply: 2 * N^3 operations for NxN matrices
    operations = 2 * size**3 * iterations
    tflops = (operations / elapsed) / 1e12

    print(f"Matrix size: {size}x{size}")
    print(f"Iterations: {iterations}")
    print(f"Time: {elapsed:.2f}s")
    print(f"TFLOPS: {tflops:.2f}")

    return tflops

if __name__ == "__main__":
    print("=" * 70)
    print("GPU TFLOPS Benchmark (FP16)")
    print("=" * 70)

    for size in [2048, 4096, 8192, 16384]:
        tflops = benchmark_matmul(size, iterations=50 if size < 16384 else 10)
        print("-" * 70)
```

**Learning goals:**
- Measure raw compute performance
- Understand TFLOPS metric
- Compare with theoretical peak performance

---

### Exercise 3: vLLM Inference Benchmark

**File**: `benchmarks/vllm_benchmark.py`

```python
#!/usr/bin/env python3
import torch
from vllm import LLM, SamplingParams
import time
import json

def benchmark_vllm(model_name, num_prompts=100, max_tokens=128):
    """Benchmark vLLM inference performance"""

    print(f"\nBenchmarking: {model_name}")
    print("=" * 70)

    # Initialize vLLM
    start_load = time.time()
    llm = LLM(
        model=model_name,
        gpu_memory_utilization=0.9,
        max_num_batched_tokens=8192,
        dtype="float16"
    )
    load_time = time.time() - start_load

    print(f"Model load time: {load_time:.2f}s")

    # Generate prompts
    prompts = [f"Write a story about {i}: " for i in range(num_prompts)]
    sampling_params = SamplingParams(
        max_tokens=max_tokens,
        temperature=0.0  # Deterministic for benchmarking
    )

    # Warm up
    _ = llm.generate(prompts[:5], sampling_params)

    # Benchmark
    start = time.time()
    outputs = llm.generate(prompts, sampling_params)
    elapsed = time.time() - start

    # Calculate metrics
    total_tokens = sum(len(output.outputs[0].token_ids) for output in outputs)
    throughput = total_tokens / elapsed
    latency_per_request = elapsed / num_prompts

    # Memory usage
    memory_used = torch.cuda.memory_allocated() / 1e9
    memory_total = torch.cuda.get_device_properties(0).total_memory / 1e9
    memory_util = (memory_used / memory_total) * 100

    results = {
        "model": model_name,
        "num_prompts": num_prompts,
        "max_tokens": max_tokens,
        "load_time_s": load_time,
        "inference_time_s": elapsed,
        "total_tokens": total_tokens,
        "throughput_tokens_per_sec": throughput,
        "latency_per_request_ms": latency_per_request * 1000,
        "memory_used_gb": memory_used,
        "memory_utilization_pct": memory_util
    }

    print(f"Total tokens: {total_tokens:,}")
    print(f"Throughput: {throughput:.2f} tokens/sec")
    print(f"Latency per request: {latency_per_request*1000:.2f} ms")
    print(f"Memory used: {memory_used:.2f} GB ({memory_util:.1f}%)")
    print("=" * 70)

    return results

if __name__ == "__main__":
    models = [
        "gpt2",                          # Small baseline
        "facebook/opt-1.3b",             # Medium model
        # "meta-llama/Llama-2-7b-hf",   # Large model (requires HF token)
    ]

    all_results = []
    for model in models:
        try:
            result = benchmark_vllm(model, num_prompts=50)
            all_results.append(result)
        except Exception as e:
            print(f"Error benchmarking {model}: {e}")

    # Save results
    with open("benchmark_results.json", "w") as f:
        json.dump(all_results, f, indent=2)

    print("\nResults saved to: benchmark_results.json")
```

**Learning goals:**
- Measure inference throughput
- Analyze memory usage patterns
- Compare different model sizes

---

### Exercise 4: Cost Analysis

**File**: `benchmarks/cost_analysis.py`

```python
#!/usr/bin/env python3
import json

# AWS GPU instance pricing (us-west-2, on-demand)
GPU_PRICING = {
    "g4dn.xlarge": {"gpu": "T4", "cost_per_hour": 0.526, "vram_gb": 16},
    "g6.2xlarge": {"gpu": "L4", "cost_per_hour": 1.10, "vram_gb": 24},
    "g5.xlarge": {"gpu": "A10G", "cost_per_hour": 1.006, "vram_gb": 24},
    "p3.2xlarge": {"gpu": "V100", "cost_per_hour": 3.06, "vram_gb": 16},
    "p4d.24xlarge": {"gpu": "8x A100", "cost_per_hour": 32.77, "vram_gb": 320},
}

def analyze_cost_performance(benchmark_results, instance_type):
    """Calculate cost per million tokens"""

    pricing = GPU_PRICING[instance_type]

    print(f"\n{'='*70}")
    print(f"Cost Analysis: {instance_type} ({pricing['gpu']})")
    print(f"{'='*70}")

    for result in benchmark_results:
        model = result["model"]
        throughput = result["throughput_tokens_per_sec"]

        # Cost calculations
        tokens_per_hour = throughput * 3600
        cost_per_million_tokens = (pricing["cost_per_hour"] / tokens_per_hour) * 1_000_000
        tokens_per_dollar = tokens_per_hour / pricing["cost_per_hour"]

        print(f"\nModel: {model}")
        print(f"  Throughput: {throughput:.2f} tokens/sec")
        print(f"  Tokens/hour: {tokens_per_hour:,.0f}")
        print(f"  Cost per 1M tokens: ${cost_per_million_tokens:.4f}")
        print(f"  Tokens per dollar: {tokens_per_dollar:,.0f}")

    print(f"{'='*70}")

if __name__ == "__main__":
    # Load benchmark results
    try:
        with open("benchmark_results.json") as f:
            results = json.load(f)
    except:
        print("No benchmark results found. Run vllm_benchmark.py first.")
        exit(1)

    # Analyze for your instance type
    instance_type = "g4dn.xlarge"  # Change to your instance type
    analyze_cost_performance(results, instance_type)
```

**Learning goals:**
- Calculate cost per million tokens
- Compare performance per dollar
- Make cost-effective GPU choices

---

### Exercise 5: Batch Size Optimization

**File**: `benchmarks/batch_optimization.py`

```python
#!/usr/bin/env python3
from vllm import LLM, SamplingParams
import time
import matplotlib.pyplot as plt

def benchmark_batch_sizes(model_name="gpt2"):
    """Find optimal batch size for throughput"""

    llm = LLM(model=model_name, gpu_memory_utilization=0.9)
    sampling_params = SamplingParams(max_tokens=50, temperature=0)

    batch_sizes = [1, 4, 8, 16, 32, 64, 128]
    results = []

    print(f"\nBatch Size Optimization: {model_name}")
    print("=" * 70)

    for batch_size in batch_sizes:
        try:
            prompts = [f"Test prompt {i}" for i in range(batch_size)]

            # Warm up
            _ = llm.generate(prompts[:min(5, batch_size)], sampling_params)

            # Benchmark
            start = time.time()
            outputs = llm.generate(prompts, sampling_params)
            elapsed = time.time() - start

            total_tokens = sum(len(out.outputs[0].token_ids) for out in outputs)
            throughput = total_tokens / elapsed
            latency = elapsed / batch_size * 1000  # ms per request

            results.append({
                "batch_size": batch_size,
                "throughput": throughput,
                "latency_ms": latency
            })

            print(f"Batch {batch_size:3d}: {throughput:7.2f} tok/s, {latency:6.2f} ms/req")

        except Exception as e:
            print(f"Batch {batch_size}: OOM or error - {e}")
            break

    print("=" * 70)

    # Find optimal
    optimal = max(results, key=lambda x: x["throughput"])
    print(f"\nOptimal batch size: {optimal['batch_size']}")
    print(f"Max throughput: {optimal['throughput']:.2f} tokens/sec")

    return results

if __name__ == "__main__":
    results = benchmark_batch_sizes()
```

**Learning goals:**
- Find optimal batch size
- Understand throughput vs latency tradeoff
- Identify memory limits

---

## 🎓 Challenges

### Challenge 1: Multi-GPU Comparison
Deploy and benchmark 3 different GPU types:
- T4 (g4dn.xlarge)
- L4 (g6.2xlarge)
- A10G (g5.xlarge)

Compare:
- Throughput for same model
- Cost per million tokens
- Power efficiency

### Challenge 2: Model Size Analysis
Test how different model sizes perform on the same GPU:
- GPT-2 (124M parameters)
- OPT-1.3B (1.3B parameters)
- Llama-2-7B (7B parameters)

Analyze:
- Memory requirements
- Throughput scaling
- Optimal model size for GPU

### Challenge 3: Configuration Tuning
For your GPU, find optimal vLLM configuration:
- Test different `gpu_memory_utilization` values (0.7, 0.8, 0.9, 0.95)
- Test different `max_num_batched_tokens`
- Test FP16 vs BF16 vs INT8
- Document best configuration

## 📊 Performance Baselines

**Expected Results (approximate)**:

| GPU | Model | Throughput | Cost/1M tokens | Memory Used |
|-----|-------|-----------|----------------|-------------|
| T4 | GPT-2 | ~200 tok/s | $0.73 | 2 GB |
| T4 | Llama-2-7B | ~50 tok/s | $2.92 | 14 GB |
| L4 | Llama-2-7B | ~120 tok/s | $2.54 | 14 GB |
| L4 | Llama-2-70B | ~15 tok/s | ~$20 | 150 GB (needs 4x L4) |
| A100 | Llama-2-70B | ~60 tok/s | ~$15 | 140 GB |

*Note: Actual results vary based on configuration and prompt length*

## 🐛 Troubleshooting

### Out of Memory During Benchmarks

```python
# Reduce gpu_memory_utilization
llm = LLM(model="...", gpu_memory_utilization=0.7)  # Instead of 0.9

# Reduce batch size
benchmark_batch_sizes = [1, 4, 8, 16]  # Instead of up to 128

# Use smaller model for testing
model = "gpt2"  # Instead of llama-70b
```

### Inconsistent Results

```bash
# Clear GPU memory between tests
python3 -c "import torch; torch.cuda.empty_cache()"

# Restart Python process
# Reboot instance if needed
sudo reboot
```

### Low GPU Utilization

```python
# Increase batch size
max_num_batched_tokens=16384  # Instead of 8192

# Increase concurrent requests
max_num_seqs=512  # Instead of 256

# Check if CPU bottlenecked
htop  # Check CPU usage
```

## 💰 Benchmarking Cost Estimate

| Instance Type | GPU | Cost/Hour | 1 Hour Testing |
|--------------|-----|-----------|----------------|
| g4dn.xlarge | T4 | $0.53 | $0.53 |
| g6.2xlarge | L4 | $1.10 | $1.10 |
| g5.xlarge | A10G | $1.01 | $1.01 |
| p3.2xlarge | V100 | $3.06 | $3.06 |

**Total for all 4 GPUs**: ~$6/hour

**Budget-friendly approach**: Test one GPU at a time, ~$1-3 total

## 📖 Additional Resources

- [NVIDIA GPU Comparison](https://www.nvidia.com/en-us/data-center/products/)
- [vLLM Performance Guide](https://docs.vllm.ai/en/latest/performance/index.html)
- [AWS GPU Pricing](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing)
- [MLPerf Inference Benchmarks](https://mlcommons.org/en/inference-edge-31/)

## ⏭️ Next Steps

After completing this module:

1. Apply findings to production deployments
2. Optimize costs based on your workload
3. Combine with Module 3 for distributed benchmarking
4. Use research tools to deep-dive into bottlenecks

## 🧹 Cleanup

```bash
cd terraform
terraform destroy
```

---

**Ready to benchmark?** Run `./deploy.sh` to get started! 📊🚀
