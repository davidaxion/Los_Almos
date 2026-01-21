#!/bin/bash
set -e

PROJECT_NAME="${project_name}"

echo "==========================================="
echo "Setting up GPU Benchmarking Environment"
echo "==========================================="

# Update system
apt-get update

# Install Python packages
pip3 install --upgrade pip
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip3 install transformers vllm
pip3 install nvidia-ml-py3 psutil matplotlib pandas

# Create benchmarks directory
mkdir -p /home/ubuntu/benchmarks/results
cd /home/ubuntu/benchmarks

# Create all benchmark scripts from the README examples
# (The actual Python files from the README exercises)

# Script 1: GPU Specs
cat > gpu_specs.py <<'SCRIPT1'
#!/usr/bin/env python3
import torch
import subprocess

def get_gpu_specs():
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
        "memory_clock_mhz": props.memory_clock_rate / 1000,
        "memory_bandwidth_gb_s": (props.memory_clock_rate * props.memory_bus_width * 2) / 8 / 1e6
    }

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

    print("=" * 70)
    print("GPU Specifications")
    print("=" * 70)
    for key, value in specs.items():
        print(f"{key:25}: {value}")
    print("=" * 70)

    return specs

if __name__ == "__main__":
    get_gpu_specs()
SCRIPT1

# Script 2: TFLOPS Benchmark
cat > tflops_benchmark.py <<'SCRIPT2'
#!/usr/bin/env python3
import torch
import time

def benchmark_matmul(size=8192, iterations=100):
    device = torch.device('cuda')
    A = torch.randn(size, size, dtype=torch.float16, device=device)
    B = torch.randn(size, size, dtype=torch.float16, device=device)

    for _ in range(10):
        C = torch.matmul(A, B)
    torch.cuda.synchronize()

    start = time.time()
    for _ in range(iterations):
        C = torch.matmul(A, B)
    torch.cuda.synchronize()
    elapsed = time.time() - start

    operations = 2 * size**3 * iterations
    tflops = (operations / elapsed) / 1e12

    print(f"Matrix size: {size}x{size}")
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
SCRIPT2

# Script 3: vLLM Benchmark
cat > vllm_benchmark.py <<'SCRIPT3'
#!/usr/bin/env python3
import torch
from vllm import LLM, SamplingParams
import time
import json

def benchmark_vllm(model_name, num_prompts=100, max_tokens=128):
    print(f"\nBenchmarking: {model_name}")
    print("=" * 70)

    start_load = time.time()
    llm = LLM(
        model=model_name,
        gpu_memory_utilization=0.9,
        max_num_batched_tokens=8192,
        dtype="float16"
    )
    load_time = time.time() - start_load
    print(f"Model load time: {load_time:.2f}s")

    prompts = [f"Write a story about {i}: " for i in range(num_prompts)]
    sampling_params = SamplingParams(max_tokens=max_tokens, temperature=0.0)

    _ = llm.generate(prompts[:5], sampling_params)

    start = time.time()
    outputs = llm.generate(prompts, sampling_params)
    elapsed = time.time() - start

    total_tokens = sum(len(output.outputs[0].token_ids) for output in outputs)
    throughput = total_tokens / elapsed
    latency_per_request = elapsed / num_prompts

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
    print(f"Latency: {latency_per_request*1000:.2f} ms/req")
    print(f"Memory: {memory_used:.2f} GB ({memory_util:.1f}%)")
    print("=" * 70)

    return results

if __name__ == "__main__":
    models = ["gpt2", "facebook/opt-1.3b"]
    all_results = []

    for model in models:
        try:
            result = benchmark_vllm(model, num_prompts=50)
            all_results.append(result)
        except Exception as e:
            print(f"Error benchmarking {model}: {e}")

    with open("results/benchmark_results.json", "w") as f:
        json.dump(all_results, f, indent=2)

    print("\nResults saved to: results/benchmark_results.json")
SCRIPT3

# Master benchmark script
cat > run_all_benchmarks.sh <<'MASTER'
#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Running Complete GPU Benchmark Suite                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p results

echo "📊 Step 1: GPU Specifications"
python3 gpu_specs.py | tee results/gpu_specs.txt
echo ""

echo "📊 Step 2: TFLOPS Benchmark"
python3 tflops_benchmark.py | tee results/tflops.txt
echo ""

echo "📊 Step 3: vLLM Inference Benchmark"
python3 vllm_benchmark.py | tee results/vllm_benchmark.txt
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  Benchmark Suite Complete! ✅                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Results saved to: ~/benchmarks/results/"
echo ""
echo "View summary:"
echo "  cat results/benchmark_summary.txt"
echo ""
MASTER

chmod +x *.py *.sh

# Create README
cat > README.md <<'README'
# GPU Benchmarking Scripts

## Quick Start

```bash
# Run all benchmarks
./run_all_benchmarks.sh

# Or run individually
python3 gpu_specs.py
python3 tflops_benchmark.py
python3 vllm_benchmark.py
```

## Results

Results are saved to `results/` directory:
- `gpu_specs.txt` - GPU hardware info
- `tflops.txt` - Compute performance
- `vllm_benchmark.txt` - Inference performance
- `benchmark_results.json` - Detailed JSON results

## Customization

Edit the scripts to:
- Change models: Edit `vllm_benchmark.py`
- Adjust batch sizes: Edit test parameters
- Add new benchmarks: Create new .py files
```
README

chown -R ubuntu:ubuntu /home/ubuntu/benchmarks

# Create welcome message
cat > /etc/motd <<MOTD
╔════════════════════════════════════════════════════════════════╗
║         GPU Benchmarking Environment - Ready! 📊               ║
╚════════════════════════════════════════════════════════════════╝

🖥️  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)
💾  VRAM: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits) MB

📁 BENCHMARKS
  cd ~/benchmarks
  ./run_all_benchmarks.sh

🔬 INDIVIDUAL TESTS
  python3 gpu_specs.py
  python3 tflops_benchmark.py
  python3 vllm_benchmark.py

📊 VIEW RESULTS
  cat ~/benchmarks/results/benchmark_summary.txt
MOTD

echo "==========================================="
echo "Benchmark environment setup complete!"
echo "==========================================="
