# Module 1: Basic GPU Setup

**Difficulty**: ⭐ Beginner
**Time**: 30 minutes
**Cost**: ~$0.50/hour
**Prerequisites**: AWS account, basic Linux knowledge

## 🎯 Learning Objectives

By the end of this module, you will:
- ✅ Launch a GPU instance on AWS
- ✅ Understand GPU instance types (T4, L4, A100)
- ✅ Install and verify NVIDIA drivers
- ✅ Run your first GPU workload with PyTorch
- ✅ Monitor GPU utilization with `nvidia-smi`
- ✅ Use vLLM for model inference
- ✅ Understand GPU memory management

## 📚 What You'll Build

A single GPU EC2 instance with:
- NVIDIA T4 GPU (16GB VRAM)
- Ubuntu 20.04 + CUDA 11.8
- PyTorch, Transformers, vLLM
- ModelLoader integration
- Jupyter Lab for interactive development

## 🚀 Quick Start

```bash
# 1. Deploy the instance
./deploy.sh

# 2. SSH into instance (from output)
ssh -i ~/.ssh/id_rsa ubuntu@<INSTANCE_IP>

# 3. Verify GPU
nvidia-smi

# 4. Run first exercise
cd ~/exercises
python3 01-hello-gpu.py
```

##

 📖 Concepts Covered

### 1. GPU Instance Types

**AWS GPU Instances:**
| Instance | GPU | VRAM | vCPUs | RAM | Cost/Hour |
|----------|-----|------|-------|-----|-----------|
| g4dn.xlarge | T4 | 16GB | 4 | 16GB | $0.526 |
| g6.2xlarge | L4 | 24GB | 8 | 32GB | $1.10 |
| g5.xlarge | A10G | 24GB | 4 | 16GB | $1.00 |
| p3.2xlarge | V100 | 16GB | 8 | 61GB | $3.06 |

**When to use each:**
- **T4**: Learning, small models, inference
- **L4**: Production inference, 70B models
- **A10G**: Training, medium models
- **V100/A100**: Large model training

### 2. CUDA & cuDNN

**CUDA**: NVIDIA's parallel computing platform
- Enables GPU-accelerated computing
- Required for PyTorch, TensorFlow
- Version compatibility matters!

**cuDNN**: Deep learning primitives library
- Optimized for CNNs, RNNs, transformers
- Auto-installed with PyTorch

### 3. GPU Memory Management

**VRAM (Video RAM)**:
- Separate from system RAM
- Stores model weights + activations
- Limited resource - manage carefully!

**Common patterns:**
```python
# Check available memory
import torch
torch.cuda.get_device_properties(0).total_memory / 1e9  # GB

# Move model to GPU
model = model.to('cuda')

# Clear GPU cache
torch.cuda.empty_cache()
```

## 🛠️ Exercises

### Exercise 1: Hello GPU World
**File**: `exercises/01-hello-gpu.py`

```python
import torch

# Check CUDA availability
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU: {torch.cuda.get_device_name(0)}")

# Create tensors on GPU
x = torch.rand(1000, 1000).cuda()
y = torch.rand(1000, 1000).cuda()

# Matrix multiplication on GPU
z = torch.matmul(x, y)
print(f"Result shape: {z.shape}")
print(f"GPU memory used: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
```

**Learning goals:**
- Verify GPU is working
- Create GPU tensors
- Perform GPU operations
- Monitor memory usage

---

### Exercise 2: Inference with vLLM
**File**: `exercises/02-vllm-inference.py`

```python
from vllm import LLM, SamplingParams

# Load small model for testing
llm = LLM(model="gpt2", gpu_memory_utilization=0.8)

# Generate text
prompts = ["The future of AI is"]
outputs = llm.generate(prompts, SamplingParams(max_tokens=50))

for output in outputs:
    print(output.outputs[0].text)
```

**Learning goals:**
- Load models on GPU
- Generate text
- Understand GPU utilization

---

### Exercise 3: Monitor GPU Performance
**File**: `exercises/03-monitor-gpu.sh`

```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Detailed stats
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv

# Temperature and power
nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv
```

**Learning goals:**
- Read nvidia-smi output
- Monitor memory usage
- Track GPU utilization
- Understand power consumption

---

### Exercise 4: Memory Management
**File**: `exercises/04-memory-management.py`

```python
import torch

def get_gpu_memory():
    return {
        'allocated': torch.cuda.memory_allocated() / 1e9,
        'reserved': torch.cuda.memory_reserved() / 1e9,
        'free': (torch.cuda.get_device_properties(0).total_memory -
                 torch.cuda.memory_allocated()) / 1e9
    }

# Create large tensor
print("Before allocation:", get_gpu_memory())
large_tensor = torch.rand(10000, 10000).cuda()
print("After allocation:", get_gpu_memory())

# Clear memory
del large_tensor
torch.cuda.empty_cache()
print("After cleanup:", get_gpu_memory())
```

**Learning goals:**
- Track memory allocation
- Clear GPU cache
- Handle OOM errors
- Optimize memory usage

---

### Exercise 5: PyTorch Basics
**File**: `exercises/05-pytorch-basics.py`

```python
import torch
import torch.nn as nn

# Simple neural network
model = nn.Sequential(
    nn.Linear(784, 128),
    nn.ReLU(),
    nn.Linear(128, 10)
).cuda()

# Forward pass
x = torch.randn(32, 784).cuda()  # Batch of 32
output = model(x)

print(f"Model on GPU: {next(model.parameters()).is_cuda}")
print(f"Output shape: {output.shape}")
```

**Learning goals:**
- Move models to GPU
- Run forward passes
- Understand batching
- Verify GPU execution

---

## 🎓 Challenges

### Challenge 1: Model Comparison
Compare inference speed on CPU vs GPU for different models.

**Task**: Measure and compare:
- GPT-2 on CPU
- GPT-2 on GPU
- Report speedup factor

### Challenge 2: Memory Limits
Find the largest model you can fit on your GPU.

**Task**:
- Start with small models
- Gradually increase size
- Document OOM error point
- Calculate VRAM requirements

### Challenge 3: Batch Size Optimization
Find optimal batch size for inference.

**Task**:
- Test batch sizes: 1, 4, 16, 32, 64
- Measure throughput (tokens/sec)
- Plot results
- Identify sweet spot

## 📊 Performance Baselines

**Expected Results (T4 GPU)**:

| Task | Metric | Expected |
|------|--------|----------|
| Matrix Mul (1000x1000) | Time | ~0.5ms |
| GPT-2 Inference | Tokens/sec | ~100 |
| GPU Memory | Available | 14.5GB |
| Utilization | During inference | 80-95% |

## 🐛 Troubleshooting

### GPU Not Detected
```bash
# Check driver
nvidia-smi

# Reinstall if needed
sudo apt-get install --reinstall nvidia-driver-535

# Reboot
sudo reboot
```

### CUDA Version Mismatch
```bash
# Check CUDA version
nvcc --version

# Check PyTorch CUDA version
python3 -c "import torch; print(torch.version.cuda)"

# Reinstall PyTorch with correct CUDA
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu118
```

### Out of Memory
```python
# Reduce batch size
batch_size = 8  # Instead of 32

# Use gradient checkpointing
model.gradient_checkpointing_enable()

# Use mixed precision
from torch.cuda.amp import autocast
with autocast():
    output = model(input)
```

## 📚 Additional Resources

- [NVIDIA GPU Cloud](https://catalog.ngc.nvidia.com/)
- [PyTorch CUDA Semantics](https://pytorch.org/docs/stable/notes/cuda.html)
- [vLLM Documentation](https://docs.vllm.ai/)
- [AWS EC2 GPU Instances](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing)

## ⏭️ Next Steps

After completing this module:

1. **Module 4: NVIDIA Benchmarking** - Learn to compare GPU performance
2. **Module 2: SLURM Cluster** - Set up job scheduling
3. **Module 3: Parallel Computing** - Scale to multiple GPUs

## 🧹 Cleanup

```bash
# From your local machine
cd terraform
terraform destroy

# Verify deletion
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance-state-name,Values=running"
```

**Remember**: Stop instance when not in use to save costs! (~$0.50/hour)

---

**Ready to start?** Run `./deploy.sh` to launch your GPU instance! 🚀
