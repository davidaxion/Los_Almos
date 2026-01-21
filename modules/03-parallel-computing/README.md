# Module 3: Parallel Computing

**Difficulty**: ⭐⭐⭐ Advanced
**Time**: 2-3 hours
**Cost**: ~$2.50/hour
**Prerequisites**: Module 1 & 2 completed, Python proficiency, understanding of neural networks

## 🎯 Learning Objectives

By the end of this module, you will:
- ✅ Understand data parallelism vs model parallelism
- ✅ Implement PyTorch Distributed Data Parallel (DDP)
- ✅ Configure multi-GPU training across nodes
- ✅ Use NCCL for efficient GPU communication
- ✅ Profile communication overhead and bottlenecks
- ✅ Optimize distributed training performance
- ✅ Understand gradient synchronization patterns

## 📚 What You'll Build

A multi-GPU training environment with:
- 2x GPU Nodes (g4dn.2xlarge with 1x T4 each) or (g6.2xlarge with 1x L4 each)
- Distributed PyTorch setup
- NCCL backend for GPU communication
- Shared storage for datasets
- Monitoring and profiling tools
- Example distributed training scripts

## 🚀 Quick Start

```bash
# 1. Deploy the infrastructure
./deploy.sh

# 2. SSH into first node
ssh -i ~/.ssh/id_rsa ubuntu@<NODE1_IP>

# 3. Run distributed training test
cd ~/examples
python3 distributed_hello.py

# 4. Run multi-GPU training
torchrun --nproc_per_node=2 --nnodes=2 --node_rank=0 \
  --master_addr=<NODE1_PRIVATE_IP> --master_port=29500 \
  train_distributed.py
```

## 📖 Concepts Covered

### 1. Parallelism Strategies

**Data Parallelism**:
- Split data across GPUs
- Each GPU has full model copy
- Synchronize gradients after backward pass
- **Use when**: Model fits on single GPU

**Model Parallelism**:
- Split model across GPUs
- Each GPU has part of the model
- Forward/backward passes require communication
- **Use when**: Model too large for single GPU

**Tensor Parallelism**:
- Split individual layers across GPUs
- Intra-layer parallelism
- **Use when**: Very large models (70B+)

**Pipeline Parallelism**:
- Split model into stages
- Each GPU processes different stage
- Micro-batching for efficiency
- **Use when**: Many layers, memory constrained

### 2. PyTorch Distributed Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Distributed Training                    │
│                                                           │
│  ┌──────────────────┐         ┌──────────────────┐       │
│  │   Node 1 (GPU 0) │         │   Node 2 (GPU 1) │       │
│  │                  │         │                  │       │
│  │  ┌────────────┐  │  NCCL   │  ┌────────────┐  │       │
│  │  │  Model     │  │◄────────►│  │  Model     │  │       │
│  │  │  Copy      │  │         │  │  Copy      │  │       │
│  │  └────────────┘  │         │  └────────────┘  │       │
│  │       │          │         │       │          │       │
│  │  ┌────▼────────┐ │         │  ┌────▼────────┐ │       │
│  │  │  Batch 1    │ │         │  │  Batch 2    │ │       │
│  │  │  (Forward)  │ │         │  │  (Forward)  │ │       │
│  │  └────┬────────┘ │         │  └────┬────────┘ │       │
│  │       │          │         │       │          │       │
│  │  ┌────▼────────┐ │         │  ┌────▼────────┐ │       │
│  │  │ Gradients  │ │         │  │ Gradients  │ │       │
│  │  └────┬────────┘ │         │  └────┬────────┘ │       │
│  │       │          │         │       │          │       │
│  └───────┼──────────┘         └───────┼──────────┘       │
│          │                            │                  │
│          └────────►AllReduce◄─────────┘                  │
│                   (Average gradients)                    │
│                                                           │
│          ┌───────────────────────┐                        │
│          │   Update model        │                        │
│          │   (Identical on both) │                        │
│          └───────────────────────┘                        │
└─────────────────────────────────────────────────────────┘
```

### 3. NCCL (NVIDIA Collective Communications Library)

**What is NCCL?**
- Optimized library for multi-GPU communication
- Implements collective operations (AllReduce, Broadcast, etc.)
- Hardware-accelerated (uses NVLink when available)
- Automatically selects best communication strategy

**Common Operations**:
- **AllReduce**: Combine values from all GPUs (e.g., average gradients)
- **Broadcast**: Send data from one GPU to all
- **AllGather**: Collect data from all GPUs
- **ReduceScatter**: Reduce and distribute results

### 4. Communication Patterns

```python
# AllReduce (most common for gradient sync)
# Before: GPU0=[1,2,3], GPU1=[4,5,6]
# After:  GPU0=[2.5,3.5,4.5], GPU1=[2.5,3.5,4.5]

# Broadcast
# Before: GPU0=[1,2,3], GPU1=[?,?,?]
# After:  GPU0=[1,2,3], GPU1=[1,2,3]

# AllGather
# Before: GPU0=[1,2], GPU1=[3,4]
# After:  GPU0=[1,2,3,4], GPU1=[1,2,3,4]
```

## 🛠️ Exercises

### Exercise 1: Distributed Hello World

**File**: `examples/distributed_hello.py`

```python
import torch
import torch.distributed as dist
import os

def setup():
    # Initialize distributed process group
    dist.init_process_group(backend='nccl')

def cleanup():
    dist.destroy_process_group()

def main():
    setup()

    rank = dist.get_rank()
    world_size = dist.get_world_size()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    print(f"Hello from rank {rank}/{world_size} on device {device}")

    # Simple tensor operation
    tensor = torch.ones(10).to(device) * rank
    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

    print(f"Rank {rank}: After AllReduce: {tensor[0].item()}")

    cleanup()

if __name__ == "__main__":
    main()
```

**Run**:
```bash
# On Node 1
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=<NODE1_IP> --master_port=29500 \
  distributed_hello.py

# On Node 2 (different terminal)
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=1 \
  --master_addr=<NODE1_IP> --master_port=29500 \
  distributed_hello.py
```

**Learning goals:**
- Initialize distributed process group
- Understand rank and world_size
- Perform AllReduce operation
- Coordinate across nodes

---

### Exercise 2: Data Parallel Training

**File**: `examples/ddp_training.py`

```python
import torch
import torch.nn as nn
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader
from torch.utils.data.distributed import DistributedSampler

class SimpleModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc = nn.Sequential(
            nn.Linear(784, 512),
            nn.ReLU(),
            nn.Linear(512, 10)
        )

    def forward(self, x):
        return self.fc(x)

def setup():
    dist.init_process_group(backend='nccl')

def cleanup():
    dist.destroy_process_group()

def train():
    setup()

    rank = dist.get_rank()
    world_size = dist.get_world_size()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    # Create model and wrap with DDP
    model = SimpleModel().to(device)
    ddp_model = DDP(model, device_ids=[device.index])

    # Create dataset with DistributedSampler
    # (ensures each GPU gets different data)
    dataset = torch.randn(1000, 784)  # Fake data
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
    dataloader = DataLoader(dataset, batch_size=32, sampler=sampler)

    optimizer = torch.optim.Adam(ddp_model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    # Training loop
    for epoch in range(5):
        sampler.set_epoch(epoch)  # Important for shuffling

        for batch_idx, data in enumerate(dataloader):
            data = data.to(device)
            labels = torch.randint(0, 10, (data.size(0),)).to(device)

            optimizer.zero_grad()
            output = ddp_model(data)
            loss = criterion(output, labels)
            loss.backward()  # Gradients automatically synchronized!
            optimizer.step()

            if rank == 0 and batch_idx % 10 == 0:
                print(f"Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.4f}")

    cleanup()

if __name__ == "__main__":
    train()
```

**Learning goals:**
- Use DistributedDataParallel (DDP)
- Configure DistributedSampler
- Automatic gradient synchronization
- Coordinate training across GPUs

---

### Exercise 3: Communication Profiling

**File**: `examples/profile_communication.py`

```python
import torch
import torch.distributed as dist
import time

def setup():
    dist.init_process_group(backend='nccl')

def benchmark_allreduce(tensor_size, num_iterations=100):
    rank = dist.get_rank()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    # Create tensor
    tensor = torch.randn(tensor_size).to(device)

    # Warm up
    for _ in range(10):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

    torch.cuda.synchronize()

    # Benchmark
    start = time.time()
    for _ in range(num_iterations):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
    torch.cuda.synchronize()
    end = time.time()

    avg_time = (end - start) / num_iterations * 1000  # ms
    bandwidth = (tensor_size * 4 * 2) / (avg_time / 1000) / 1e9  # GB/s (4 bytes per float, 2x for send+recv)

    if rank == 0:
        print(f"Tensor size: {tensor_size:,} | Avg time: {avg_time:.2f} ms | Bandwidth: {bandwidth:.2f} GB/s")

def main():
    setup()

    if dist.get_rank() == 0:
        print("Benchmarking AllReduce performance...")
        print("-" * 70)

    # Test different tensor sizes
    for size in [1000, 10000, 100000, 1000000, 10000000]:
        benchmark_allreduce(size)

    dist.destroy_process_group()

if __name__ == "__main__":
    main()
```

**Learning goals:**
- Measure communication overhead
- Understand bandwidth vs latency
- Identify communication bottlenecks
- Optimize tensor sizes

---

### Exercise 4: Gradient Accumulation

**File**: `examples/gradient_accumulation.py`

```python
import torch
import torch.nn as nn
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

# Gradient accumulation allows training with larger effective batch sizes
# Useful when GPU memory is limited

def train_with_accumulation():
    dist.init_process_group(backend='nccl')
    rank = dist.get_rank()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    model = nn.Linear(1000, 10).to(device)
    ddp_model = DDP(model, device_ids=[device.index])
    optimizer = torch.optim.Adam(ddp_model.parameters())

    accumulation_steps = 4  # Effective batch size = batch_size * accumulation_steps

    for step in range(100):
        for accum_step in range(accumulation_steps):
            # Forward pass
            data = torch.randn(32, 1000).to(device)
            labels = torch.randint(0, 10, (32,)).to(device)

            output = ddp_model(data)
            loss = nn.CrossEntropyLoss()(output, labels)

            # Scale loss (important!)
            loss = loss / accumulation_steps
            loss.backward()

        # Update weights after accumulating gradients
        optimizer.step()
        optimizer.zero_grad()

        if rank == 0 and step % 10 == 0:
            print(f"Step {step}, Loss: {loss.item() * accumulation_steps:.4f}")

    dist.destroy_process_group()

if __name__ == "__main__":
    train_with_accumulation()
```

**Learning goals:**
- Implement gradient accumulation
- Train with larger effective batch sizes
- Understand memory vs compute tradeoffs
- Scale to larger models

---

### Exercise 5: Model Parallelism Basics

**File**: `examples/model_parallelism.py`

```python
import torch
import torch.nn as nn

# Simple model parallelism example
# Split model across 2 GPUs

class ModelParallelNet(nn.Module):
    def __init__(self):
        super().__init__()
        # First part on GPU 0
        self.layer1 = nn.Sequential(
            nn.Linear(1000, 512),
            nn.ReLU()
        ).to('cuda:0')

        # Second part on GPU 1
        self.layer2 = nn.Sequential(
            nn.Linear(512, 10)
        ).to('cuda:1')

    def forward(self, x):
        # Forward pass across GPUs
        x = x.to('cuda:0')
        x = self.layer1(x)

        x = x.to('cuda:1')  # Transfer to second GPU
        x = self.layer2(x)
        return x

def train():
    model = ModelParallelNet()
    optimizer = torch.optim.Adam(model.parameters())

    for step in range(100):
        data = torch.randn(32, 1000)  # On CPU
        labels = torch.randint(0, 10, (32,)).to('cuda:1')

        optimizer.zero_grad()
        output = model(data)
        loss = nn.CrossEntropyLoss()(output, labels)
        loss.backward()
        optimizer.step()

        if step % 10 == 0:
            print(f"Step {step}, Loss: {loss.item():.4f}")

if __name__ == "__main__":
    train()
```

**Learning goals:**
- Split model across multiple GPUs
- Understand device-to-device transfers
- Recognize pipeline bubbles
- Identify when to use model parallelism

---

## 🎓 Challenges

### Challenge 1: Scaling Efficiency
Measure training throughput with 1, 2, and 4 GPUs:
- Record samples/second
- Calculate speedup vs single GPU
- Identify scaling bottlenecks
- Plot scaling curve

### Challenge 2: Communication Optimization
Reduce communication overhead:
- Implement gradient compression
- Test different batch sizes
- Measure communication vs computation ratio
- Optimize for your specific model

### Challenge 3: Hybrid Parallelism
Combine data and model parallelism:
- Use 4 GPUs total
- Data parallel across 2 nodes
- Model parallel within each node
- Train a medium-sized transformer

## 📊 Performance Baselines

**Expected Results (2x T4 GPUs)**:

| Metric | 1 GPU | 2 GPUs | Ideal |
|--------|-------|--------|-------|
| Samples/sec | 100 | 180 | 200 |
| Scaling efficiency | 100% | 90% | 100% |
| Communication overhead | 0% | ~10% | 0% |
| AllReduce latency (1MB) | N/A | ~1ms | <0.5ms |

**Communication Bandwidth** (approximate):
- PCIe 3.0 x16: ~15 GB/s
- NVLink (V100/A100): ~300 GB/s
- Network (10 GbE): ~1 GB/s

## 🐛 Troubleshooting

### Processes Hang at Initialization

```bash
# Check network connectivity
ping <other_node_ip>

# Verify ports are open
nc -zv <master_addr> 29500

# Check NCCL debug output
export NCCL_DEBUG=INFO
python distributed_script.py
```

### NCCL Errors

```bash
# Set NCCL socket interface (if multiple network interfaces)
export NCCL_SOCKET_IFNAME=eth0

# Increase timeout for slow networks
export NCCL_TIMEOUT=600

# Disable NCCL P2P if causing issues
export NCCL_P2P_DISABLE=1
```

### Out of Memory with DDP

```python
# Reduce batch size
batch_size = 16  # Instead of 32

# Use gradient checkpointing
model.gradient_checkpointing_enable()

# Use mixed precision
from torch.cuda.amp import autocast, GradScaler
scaler = GradScaler()

with autocast():
    output = model(input)
    loss = criterion(output, labels)

scaler.scale(loss).backward()
scaler.step(optimizer)
scaler.update()
```

### Rank Mismatch Errors

```bash
# Ensure all processes use same world_size and unique ranks
# Node 1: --node_rank=0
# Node 2: --node_rank=1

# Verify with:
echo "I am rank $RANK of $WORLD_SIZE"
```

## 💰 Cost Breakdown

| Resource | Type | Cost/Hour | Monthly (24/7) |
|----------|------|-----------|----------------|
| Node 1 | g4dn.2xlarge (1 GPU) | $0.752 | ~$543 |
| Node 2 | g4dn.2xlarge (1 GPU) | $0.752 | ~$543 |
| EFS Storage | 100GB | ~$0.003/hr | ~$2/month |
| **Total** | | **~$1.50/hr** | **~$1,088/month** |

**Upgrade to L4 (g6.2xlarge)**: ~$2.20/hour total

**Cost Optimization:**
- Stop instances when not training
- Use Spot Instances (70% savings)
- Delete cluster after experiments

## 🔗 Integration with Research

This module connects with research materials:

- **NCCL Tracing**: Use eBPF to trace NCCL collective operations
  - See `shared/research/libcuda-hooking/ebpf/`

- **Communication Profiling**: Analyze inter-GPU data transfers
  - Hook CUDA memory copies between devices

- **Performance Analysis**: Identify communication bottlenecks
  - Compare with theoretical bandwidth limits

## 📖 Additional Resources

- [PyTorch Distributed Tutorial](https://pytorch.org/tutorials/beginner/dist_overview.html)
- [NCCL Documentation](https://docs.nvidia.com/deeplearning/nccl/)
- [DeepSpeed](https://www.deepspeed.ai/) - Advanced distributed training
- [Megatron-LM](https://github.com/NVIDIA/Megatron-LM) - Large model training

## ⏭️ Next Steps

After completing this module:

1. **Module 4: NVIDIA Benchmarking** - Compare distributed training performance
2. **Research**: Apply eBPF tracing to analyze NCCL operations
3. **Advanced**: Explore DeepSpeed or Megatron-LM

## 🧹 Cleanup

```bash
cd terraform
terraform destroy

# Confirm deletion
# Type 'yes'
```

---

**Ready to scale?** Run `./deploy.sh` to create your distributed environment! 🚀
