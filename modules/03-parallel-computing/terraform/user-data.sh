#!/bin/bash
set -e

NODE_INDEX="${node_index}"
PROJECT_NAME="${project_name}"

echo "==========================================="
echo "Setting up GPU Node $NODE_INDEX"
echo "==========================================="

# Update system
apt-get update

# Install Python packages for distributed training
pip3 install --upgrade pip
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip3 install transformers accelerate datasets
pip3 install nvidia-ml-py3

# Create examples directory
mkdir -p /home/ubuntu/examples
cd /home/ubuntu/examples

# Example 1: Distributed Hello World
cat > distributed_hello.py <<'EOF'
#!/usr/bin/env python3
import torch
import torch.distributed as dist
import os

def setup():
    dist.init_process_group(backend='nccl')

def cleanup():
    dist.destroy_process_group()

def main():
    setup()

    rank = dist.get_rank()
    world_size = dist.get_world_size()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    print(f"=" * 60)
    print(f"Hello from rank {rank}/{world_size}")
    print(f"Device: {device} ({torch.cuda.get_device_name(device)})")
    print(f"=" * 60)

    # Simple tensor operation
    tensor = torch.ones(10).to(device) * rank
    print(f"Rank {rank}: Before AllReduce: {tensor[:3].tolist()}")

    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
    print(f"Rank {rank}: After AllReduce: {tensor[:3].tolist()}")

    cleanup()

if __name__ == "__main__":
    main()
EOF

# Example 2: DDP Training
cat > ddp_training.py <<'EOF'
#!/usr/bin/env python3
import torch
import torch.nn as nn
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import TensorDataset, DataLoader
from torch.utils.data.distributed import DistributedSampler
import time

class SimpleModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc = nn.Sequential(
            nn.Linear(784, 512),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(512, 256),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(256, 10)
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

    if rank == 0:
        print("=" * 60)
        print("Distributed Data Parallel Training")
        print(f"World size: {world_size}")
        print("=" * 60)

    # Create model and wrap with DDP
    model = SimpleModel().to(device)
    ddp_model = DDP(model, device_ids=[device.index])

    # Create fake dataset
    data_size = 10000
    data = torch.randn(data_size, 784)
    labels = torch.randint(0, 10, (data_size,))
    dataset = TensorDataset(data, labels)

    # DistributedSampler ensures each GPU gets different data
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
    dataloader = DataLoader(dataset, batch_size=64, sampler=sampler)

    optimizer = torch.optim.Adam(ddp_model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    # Training loop
    for epoch in range(5):
        sampler.set_epoch(epoch)
        epoch_loss = 0.0
        start_time = time.time()

        for batch_idx, (data_batch, label_batch) in enumerate(dataloader):
            data_batch = data_batch.to(device)
            label_batch = label_batch.to(device)

            optimizer.zero_grad()
            output = ddp_model(data_batch)
            loss = criterion(output, label_batch)
            loss.backward()  # Gradients automatically synchronized!
            optimizer.step()

            epoch_loss += loss.item()

        epoch_time = time.time() - start_time
        avg_loss = epoch_loss / len(dataloader)

        if rank == 0:
            print(f"Epoch {epoch+1}/5 | Loss: {avg_loss:.4f} | Time: {epoch_time:.2f}s")

    if rank == 0:
        print("=" * 60)
        print("Training complete!")
        print("=" * 60)

    cleanup()

if __name__ == "__main__":
    train()
EOF

# Example 3: Communication profiling
cat > profile_communication.py <<'EOF'
#!/usr/bin/env python3
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
    data_size = tensor_size * 4  # 4 bytes per float32
    bandwidth = (data_size * 2) / (avg_time / 1000) / 1e9  # GB/s (2x for send+recv)

    if rank == 0:
        size_mb = data_size / 1e6
        print(f"Size: {size_mb:7.2f} MB | Time: {avg_time:6.2f} ms | Bandwidth: {bandwidth:5.2f} GB/s")

def main():
    setup()

    if dist.get_rank() == 0:
        print("=" * 70)
        print("NCCL AllReduce Performance Benchmark")
        print("=" * 70)

    # Test different tensor sizes
    sizes = [1000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]
    for size in sizes:
        benchmark_allreduce(size)

    if dist.get_rank() == 0:
        print("=" * 70)

    dist.destroy_process_group()

if __name__ == "__main__":
    main()
EOF

# Example 4: Launch script
cat > launch_distributed.sh <<'EOF'
#!/bin/bash

# Simple launcher for distributed training
# Automatically detects other nodes and launches training

MASTER_ADDR="$1"
MASTER_PORT="${2:-29500}"

if [ -z "$MASTER_ADDR" ]; then
    echo "Usage: $0 <master_addr> [master_port]"
    echo "Example: $0 172.31.1.100 29500"
    exit 1
fi

# Detect node rank (simple heuristic)
MY_IP=$(hostname -I | awk '{print $1}')
if [ "$MY_IP" == "$MASTER_ADDR" ]; then
    NODE_RANK=0
else
    NODE_RANK=1
fi

echo "Launching distributed training..."
echo "Master: $MASTER_ADDR:$MASTER_PORT"
echo "My IP: $MY_IP"
echo "My Rank: $NODE_RANK"

torchrun --nproc_per_node=1 --nnodes=2 --node_rank=$NODE_RANK \
  --master_addr=$MASTER_ADDR --master_port=$MASTER_PORT \
  distributed_hello.py
EOF

chmod +x *.py *.sh

# Create README
cat > README.md <<'EOF'
# Distributed Training Examples

## Quick Start

### Run Distributed Hello World

Terminal 1 (Node 0):
```bash
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=<NODE0_PRIVATE_IP> --master_port=29500 \
  distributed_hello.py
```

Terminal 2 (Node 1):
```bash
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=1 \
  --master_addr=<NODE0_PRIVATE_IP> --master_port=29500 \
  distributed_hello.py
```

### Run DDP Training

```bash
# Same torchrun command but with ddp_training.py
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=<NODE0_PRIVATE_IP> --master_port=29500 \
  ddp_training.py
```

### Benchmark Communication

```bash
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=<NODE0_PRIVATE_IP> --master_port=29500 \
  profile_communication.py
```

## Environment Variables

```bash
# Enable NCCL debug output
export NCCL_DEBUG=INFO

# Set network interface (if multiple)
export NCCL_SOCKET_IFNAME=eth0

# Disable P2P (if causing issues)
export NCCL_P2P_DISABLE=1
```

## Monitoring

```bash
# GPU utilization
watch -n 1 nvidia-smi

# Network traffic
iftop -i eth0
```
EOF

chown -R ubuntu:ubuntu /home/ubuntu/examples

# Create welcome message
cat > /etc/motd <<MOTD
╔════════════════════════════════════════════════════════════════╗
║       Distributed GPU Training Node $NODE_INDEX - Ready!                 ║
╚════════════════════════════════════════════════════════════════╝

🖥️  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)
🔧  PyTorch: $(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not installed yet")
🌐  Private IP: $(hostname -I | awk '{print $1}')

📁 EXAMPLES
  cd ~/examples
  ls -la

🚀 RUN DISTRIBUTED TRAINING
  See ~/examples/README.md for instructions

🔍 MONITOR GPU
  nvidia-smi
  watch -n 1 nvidia-smi
MOTD

echo "==========================================="
echo "Node $NODE_INDEX setup complete!"
echo "==========================================="
