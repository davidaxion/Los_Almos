#!/bin/bash
set -e

# User Data Script for Module 1: Basic GPU Setup
# Installs ML frameworks and creates learning exercises

echo "========================================"
echo "Module 1: Basic GPU Setup - Initializing"
echo "========================================"

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    git \
    htop \
    tmux \
    vim \
    curl \
    wget \
    build-essential

# Install Python packages
pip3 install --upgrade pip
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip3 install transformers accelerate vllm jupyterlab \
    numpy pandas matplotlib seaborn \
    ipywidgets tqdm

# Create exercises directory
mkdir -p /home/ubuntu/exercises
cd /home/ubuntu/exercises

# Exercise 1: Hello GPU
cat > 01-hello-gpu.py <<'EOF'
#!/usr/bin/env python3
"""
Exercise 1: Hello GPU World
Verify GPU is working and perform basic operations
"""
import torch
import time

print("=" * 60)
print("Exercise 1: Hello GPU World")
print("=" * 60)

# Check CUDA availability
print(f"\n✓ CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"✓ GPU: {torch.cuda.get_device_name(0)}")
    props = torch.cuda.get_device_properties(0)
    print(f"✓ VRAM: {props.total_memory / 1e9:.2f} GB")
    print(f"✓ CUDA version: {torch.version.cuda}")
else:
    print("✗ No GPU detected!")
    exit(1)

# Create tensors on GPU
print("\n" + "=" * 60)
print("Creating tensors on GPU...")
x = torch.rand(1000, 1000).cuda()
y = torch.rand(1000, 1000).cuda()
print(f"✓ Tensor X: {x.shape} on {x.device}")
print(f"✓ Tensor Y: {y.shape} on {y.device}")

# Matrix multiplication
print("\n" + "=" * 60)
print("Performing matrix multiplication...")
start = time.time()
z = torch.matmul(x, y)
torch.cuda.synchronize()
elapsed = time.time() - start

print(f"✓ Result: {z.shape}")
print(f"✓ Time: {elapsed*1000:.2f} ms")
print(f"✓ GPU memory used: {torch.cuda.memory_allocated() / 1e9:.2f} GB")

print("\n" + "=" * 60)
print("Exercise 1 Complete! ✓")
print("=" * 60)
print("\nNext: Run '02-vllm-inference.py'")
EOF

# Exercise 2: vLLM Inference
cat > 02-vllm-inference.py <<'EOF'
#!/usr/bin/env python3
"""
Exercise 2: Model Inference with vLLM
Learn to load and run models on GPU
"""
from vllm import LLM, SamplingParams
import time

print("=" * 60)
print("Exercise 2: vLLM Inference")
print("=" * 60)

# Load model
print("\nLoading GPT-2 model...")
start = time.time()
llm = LLM(model="gpt2", gpu_memory_utilization=0.8)
load_time = time.time() - start
print(f"✓ Model loaded in {load_time:.2f} seconds")

# Generate text
print("\n" + "=" * 60)
print("Generating text...")
prompts = [
    "The future of artificial intelligence is",
    "Machine learning enables us to",
    "GPU computing accelerates"
]

sampling_params = SamplingParams(
    temperature=0.8,
    top_p=0.95,
    max_tokens=50
)

start = time.time()
outputs = llm.generate(prompts, sampling_params)
gen_time = time.time() - start

# Display results
for i, output in enumerate(outputs, 1):
    print(f"\n--- Prompt {i} ---")
    print(f"Input: {output.prompt}")
    print(f"Output: {output.outputs[0].text}")
    tokens = len(output.outputs[0].token_ids)
    print(f"Tokens: {tokens}")

print("\n" + "=" * 60)
print(f"Total generation time: {gen_time:.2f} seconds")
print(f"Tokens per second: {sum(len(o.outputs[0].token_ids) for o in outputs) / gen_time:.1f}")
print("=" * 60)
print("\nExercise 2 Complete! ✓")
print("Next: Run './03-monitor-gpu.sh'")
EOF

# Exercise 3: Monitor GPU
cat > 03-monitor-gpu.sh <<'EOF'
#!/bin/bash
# Exercise 3: Monitor GPU Performance

echo "=========================================="
echo "Exercise 3: GPU Monitoring"
echo "=========================================="

echo -e "\n1. Basic GPU Info:"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv

echo -e "\n2. Memory Usage:"
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

echo -e "\n3. GPU Utilization:"
nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv

echo -e "\n4. Temperature & Power:"
nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit --format=csv

echo -e "\n=========================================="
echo "Real-time monitoring (Ctrl+C to stop):"
echo "=========================================="
echo "Run: watch -n 1 nvidia-smi"
echo -e "\nExercise 3 Complete! ✓"
echo "Next: Run '04-memory-management.py'"
EOF

chmod +x 03-monitor-gpu.sh

# Exercise 4: Memory Management
cat > 04-memory-management.py <<'EOF'
#!/usr/bin/env python3
"""
Exercise 4: GPU Memory Management
Learn to track and manage GPU memory
"""
import torch
import gc

def get_gpu_memory():
    """Get current GPU memory stats"""
    allocated = torch.cuda.memory_allocated() / 1e9
    reserved = torch.cuda.memory_reserved() / 1e9
    total = torch.cuda.get_device_properties(0).total_memory / 1e9
    free = total - allocated
    return {
        'allocated': allocated,
        'reserved': reserved,
        'total': total,
        'free': free
    }

def print_memory(label):
    mem = get_gpu_memory()
    print(f"\n{label}:")
    print(f"  Allocated: {mem['allocated']:.2f} GB")
    print(f"  Reserved:  {mem['reserved']:.2f} GB")
    print(f"  Free:      {mem['free']:.2f} GB")
    print(f"  Total:     {mem['total']:.2f} GB")

print("=" * 60)
print("Exercise 4: GPU Memory Management")
print("=" * 60)

# Initial state
print_memory("Initial state")

# Allocate large tensor
print("\n" + "=" * 60)
print("Allocating 10000x10000 tensor...")
large_tensor = torch.rand(10000, 10000).cuda()
print_memory("After allocation")

# Allocate another
print("\n" + "=" * 60)
print("Allocating second tensor...")
another_tensor = torch.rand(5000, 5000).cuda()
print_memory("After second allocation")

# Delete tensors
print("\n" + "=" * 60)
print("Deleting tensors...")
del large_tensor
del another_tensor
gc.collect()
print_memory("After deletion (before cache clear)")

# Clear cache
print("\n" + "=" * 60)
print("Clearing GPU cache...")
torch.cuda.empty_cache()
print_memory("After cache clear")

print("\n" + "=" * 60)
print("Exercise 4 Complete! ✓")
print("=" * 60)
print("\nNext: Run '05-pytorch-basics.py'")
EOF

# Exercise 5: PyTorch Basics
cat > 05-pytorch-basics.py <<'EOF'
#!/usr/bin/env python3
"""
Exercise 5: PyTorch Basics on GPU
Learn basic PyTorch operations on GPU
"""
import torch
import torch.nn as nn
import time

print("=" * 60)
print("Exercise 5: PyTorch Basics")
print("=" * 60)

# Create simple neural network
class SimpleNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(784, 256),
            nn.ReLU(),
            nn.Linear(256, 128),
            nn.ReLU(),
            nn.Linear(128, 10)
        )

    def forward(self, x):
        return self.layers(x)

# Create model and move to GPU
print("\nCreating model...")
model = SimpleNet().cuda()
print(f"✓ Model created with {sum(p.numel() for p in model.parameters())} parameters")
print(f"✓ Model on GPU: {next(model.parameters()).is_cuda}")

# Create input data
print("\n" + "=" * 60)
print("Creating batch data...")
batch_size = 32
x = torch.randn(batch_size, 784).cuda()
print(f"✓ Input shape: {x.shape}")
print(f"✓ Input on GPU: {x.is_cuda}")

# Forward pass
print("\n" + "=" * 60)
print("Running forward pass...")
start = time.time()
output = model(x)
torch.cuda.synchronize()
elapsed = time.time() - start

print(f"✓ Output shape: {output.shape}")
print(f"✓ Forward pass time: {elapsed*1000:.2f} ms")
print(f"✓ GPU memory used: {torch.cuda.memory_allocated() / 1e9:.2f} GB")

# Benchmark
print("\n" + "=" * 60)
print("Benchmarking (100 iterations)...")
start = time.time()
for _ in range(100):
    _ = model(x)
torch.cuda.synchronize()
elapsed = time.time() - start

print(f"✓ Total time: {elapsed:.2f} seconds")
print(f"✓ Average per iteration: {elapsed*10:.2f} ms")
print(f"✓ Throughput: {100 / elapsed:.1f} iterations/sec")

print("\n" + "=" * 60)
print("Exercise 5 Complete! ✓")
print("=" * 60)
print("\n🎉 All exercises complete!")
print("Check out the challenges in README.md")
EOF

# Make all exercises executable
chmod +x /home/ubuntu/exercises/*.py
chown -R ubuntu:ubuntu /home/ubuntu/exercises

# Create welcome message
cat > /etc/motd <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║          Module 1: Basic GPU Setup - Learning Environment     ║
╚════════════════════════════════════════════════════════════════╝

🖥️  GPU INFO
  nvidia-smi           - View GPU status
  watch -n 1 nvidia-smi - Real-time monitoring

📚 EXERCISES (in ~/exercises/)
  01-hello-gpu.py           - Verify GPU is working
  02-vllm-inference.py      - Model inference
  03-monitor-gpu.sh         - GPU monitoring
  04-memory-management.py   - Memory management
  05-pytorch-basics.py      - PyTorch basics

🚀 START LEARNING
  cd ~/exercises
  python3 01-hello-gpu.py

💻 JUPYTER LAB (Optional)
  jupyter lab --ip=0.0.0.0 --no-browser

📖 DOCUMENTATION
  See: modules/01-basic-gpu/README.md

EOF

echo "========================================"
echo "Module 1 initialization complete!"
echo "========================================"
echo "Exercises created in /home/ubuntu/exercises"
echo "Run 'python3 01-hello-gpu.py' to start"
echo "========================================"
