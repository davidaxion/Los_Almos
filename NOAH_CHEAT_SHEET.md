# Noah's Quick Reference Cheat Sheet

Essential commands and tips for the Los Alamos GPU learning path.

---

## 🚀 Deployment Commands

### Starting a Module
```bash
# Navigate to module
cd modules/01-basic-gpu

# Deploy infrastructure
./deploy.sh

# Wait for output showing IP address
# Then SSH (IP from output)
ssh -i ~/.ssh/id_rsa ubuntu@<INSTANCE_IP>
```

### Stopping a Module (SAVE MONEY!)
```bash
# Navigate to terraform directory
cd terraform

# Destroy everything
terraform destroy

# Confirm with 'yes'
```

### Check What's Running
```bash
# List all EC2 instances
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress]' \
  --output table
```

---

## 🖥️ GPU Commands

### Check GPU Status
```bash
# Quick check
nvidia-smi

# Detailed info
nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,temperature.gpu \
  --format=csv

# Watch in real-time (updates every 1 second)
watch -n 1 nvidia-smi

# GPU temperature and power
nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit --format=csv
```

### Python GPU Check
```python
import torch

# Check if CUDA available
print(torch.cuda.is_available())

# Get GPU name
print(torch.cuda.get_device_name(0))

# Check memory
print(f"Total: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
print(f"Allocated: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
print(f"Cached: {torch.cuda.memory_reserved() / 1e9:.2f} GB")

# Clear cache
torch.cuda.empty_cache()
```

---

## 📋 SLURM Commands (Phase 2)

### Job Submission
```bash
# Submit batch job
sbatch my_job.sh

# Submit with custom parameters
sbatch --gres=gpu:1 --mem=32G my_job.sh

# Interactive session
srun --partition=gpu --gres=gpu:1 --pty bash

# Interactive with specific resources
srun --partition=gpu --gres=gpu:1 --mem=32G --time=01:00:00 --pty bash
```

### Job Monitoring
```bash
# View queue
squeue

# Your jobs only
squeue -u ubuntu

# Detailed job info
scontrol show job <JOB_ID>

# Why is job pending?
squeue --start

# Job history
sacct
sacct --format=JobID,JobName,Partition,State,Elapsed,MaxRSS
```

### Job Management
```bash
# Cancel job
scancel <JOB_ID>

# Cancel all your jobs
scancel -u ubuntu

# Hold job
scontrol hold <JOB_ID>

# Release job
scontrol release <JOB_ID>
```

### Cluster Status
```bash
# View nodes
sinfo

# Detailed node info
sinfo -Nel

# Node details
scontrol show node

# Partition info
scontrol show partition
```

---

## 🔄 Distributed Training Commands (Phase 3)

### Launch Distributed Job

**Option 1: torchrun (recommended)**
```bash
# On Node 0 (master)
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=<MASTER_PRIVATE_IP> --master_port=29500 \
  script.py

# On Node 1 (worker)
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=1 \
  --master_addr=<MASTER_PRIVATE_IP> --master_port=29500 \
  script.py
```

**Option 2: python -m torch.distributed.launch**
```bash
python -m torch.distributed.launch \
  --nproc_per_node=1 \
  --nnodes=2 \
  --node_rank=0 \
  --master_addr=<MASTER_PRIVATE_IP> \
  --master_port=29500 \
  script.py
```

### Environment Variables
```bash
# Debug NCCL
export NCCL_DEBUG=INFO

# Set network interface
export NCCL_SOCKET_IFNAME=eth0

# Disable P2P (if issues)
export NCCL_P2P_DISABLE=1

# Set timeout (seconds)
export NCCL_TIMEOUT=600
```

### Check Network
```bash
# Test connectivity between nodes
ping <OTHER_NODE_IP>

# Check port is open
nc -zv <MASTER_IP> 29500

# View network traffic
iftop -i eth0
```

---

## 📊 Benchmarking Commands (Phase 4)

### Quick Benchmarks
```bash
# GPU specs
python3 benchmarks/gpu_specs.py

# TFLOPS
python3 benchmarks/tflops_benchmark.py

# vLLM inference
python3 benchmarks/vllm_benchmark.py

# Run all
./benchmarks/run_all_benchmarks.sh
```

### View Results
```bash
# Summary
cat benchmarks/results/benchmark_summary.txt

# JSON results
cat benchmarks/results/benchmark_results.json | jq

# Copy results to local machine
scp -i ~/.ssh/id_rsa ubuntu@<IP>:~/benchmarks/results/*.json .
```

---

## 🐛 Troubleshooting

### SSH Won't Connect
```bash
# Check instance is running
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# Check security group allows SSH
# Ensure port 22 is open from your IP

# Verify key permissions
chmod 400 ~/.ssh/id_rsa

# Use verbose mode to debug
ssh -v -i ~/.ssh/id_rsa ubuntu@<IP>
```

### GPU Not Detected
```bash
# Check driver
nvidia-smi

# If not working, reinstall
sudo apt-get install --reinstall nvidia-driver-535

# Reboot
sudo reboot
```

### Out of Memory Error
```python
# Reduce batch size
batch_size = 8  # Instead of 32

# Clear cache
import torch
torch.cuda.empty_cache()

# Reduce GPU memory utilization
llm = LLM(model="gpt2", gpu_memory_utilization=0.7)  # Instead of 0.9

# Use gradient checkpointing
model.gradient_checkpointing_enable()
```

### SLURM Job Stuck
```bash
# Check why pending
squeue -j <JOB_ID> --start

# View detailed info
scontrol show job <JOB_ID>

# Check node status
scontrol show node

# Restart SLURM (on head node)
sudo systemctl restart slurmctld

# Restart on worker
sudo systemctl restart slurmd
```

### Distributed Training Hangs
```bash
# Enable debug output
export NCCL_DEBUG=INFO

# Check both processes can communicate
ping <OTHER_NODE_IP>

# Verify MASTER_ADDR is the PRIVATE IP
echo $MASTER_ADDR

# Check firewall
sudo ufw status

# Verify ranks are correct
# Node 0: --node_rank=0
# Node 1: --node_rank=1
```

---

## 💰 Cost Control

### Check Current Costs
```bash
# List running instances with costs
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceType,LaunchTime]' \
  --output table
```

### Instance Pricing (us-west-2)
| Instance | GPU | Cost/Hour | Cost/Day |
|----------|-----|-----------|----------|
| g4dn.xlarge | T4 | $0.526 | $12.62 |
| g4dn.2xlarge | T4 | $0.752 | $18.05 |
| g6.2xlarge | L4 | $1.10 | $26.40 |
| g5.xlarge | A10G | $1.006 | $24.14 |
| p3.2xlarge | V100 | $3.06 | $73.44 |

### Stop All Instances
```bash
# Get all running instance IDs
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text

# Stop them (doesn't delete, preserves data)
aws ec2 stop-instances --instance-ids <INSTANCE_IDs>

# Or terminate (deletes everything)
aws ec2 terminate-instances --instance-ids <INSTANCE_IDs>
```

---

## 📝 Useful Python Snippets

### Quick vLLM Test
```python
from vllm import LLM, SamplingParams

llm = LLM(model="gpt2", gpu_memory_utilization=0.8)
output = llm.generate(["Hello world"], SamplingParams(max_tokens=50))
print(output[0].outputs[0].text)
```

### Benchmark Template
```python
import time
import torch

def benchmark(func, iterations=100):
    # Warm up
    for _ in range(10):
        func()
    torch.cuda.synchronize()

    # Benchmark
    start = time.time()
    for _ in range(iterations):
        func()
    torch.cuda.synchronize()
    elapsed = time.time() - start

    avg_time = elapsed / iterations
    print(f"Avg time: {avg_time*1000:.2f} ms")
    return avg_time

# Usage
def my_operation():
    x = torch.randn(1000, 1000).cuda()
    y = torch.matmul(x, x)
    return y

benchmark(my_operation)
```

### DDP Template
```python
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def setup():
    dist.init_process_group(backend='nccl')

def cleanup():
    dist.destroy_process_group()

def main():
    setup()
    rank = dist.get_rank()
    device = torch.device(f'cuda:{rank % torch.cuda.device_count()}')

    model = YourModel().to(device)
    ddp_model = DDP(model, device_ids=[device.index])

    # Training code here

    cleanup()

if __name__ == "__main__":
    main()
```

---

## 🔧 Common File Locations

### Module Directories
```
Los_Alamos/
├── modules/01-basic-gpu/
│   ├── terraform/
│   └── exercises/           # Your exercise files here
├── modules/02-slurm-cluster/
│   └── terraform/
├── modules/03-parallel-computing/
│   ├── terraform/
│   └── examples/           # Distributed training examples
└── modules/04-nvidia-benchmarking/
    ├── terraform/
    └── benchmarks/         # Benchmark scripts
```

### On EC2 Instance
```
/home/ubuntu/
├── exercises/              # Module 1 exercises
├── examples/               # Module 3 examples
├── benchmarks/             # Module 4 benchmarks
│   └── results/           # Benchmark output
└── .bashrc                # Environment setup
```

### Log Locations
```
# SLURM logs
/var/log/slurm/slurmctld.log    # Controller logs
/var/log/slurm/slurmd.log       # Worker logs

# Job output
/tmp/                           # Default SLURM output location
```

---

## ⌨️ Helpful Bash Aliases

Add these to `~/.bashrc` on EC2 instances:

```bash
# GPU monitoring
alias gpu='watch -n 1 nvidia-smi'
alias gputemp='nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader'
alias gpumem='nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader'

# SLURM shortcuts
alias sq='squeue'
alias sqa='squeue -u ubuntu'
alias si='sinfo'

# Quick Python
alias python='python3'
alias pip='pip3'

# Navigation
alias ex='cd ~/exercises'
alias bench='cd ~/benchmarks'

# Apply with: source ~/.bashrc
```

---

## 📞 Emergency Commands

### Kill All Python Processes
```bash
pkill -9 python3
```

### Force Clear GPU Memory
```bash
sudo fuser -v /dev/nvidia*
sudo kill -9 <PID>
```

### Reset SSH if Locked Out
```bash
# From AWS Console, use Session Manager
# Or reboot instance
aws ec2 reboot-instances --instance-ids <INSTANCE_ID>
```

### Save Work Before Cleanup
```bash
# Tar up your results
tar -czf results_$(date +%Y%m%d).tar.gz ~/benchmarks/results ~/exercises

# Copy to local machine
scp -i ~/.ssh/id_rsa ubuntu@<IP>:~/results_*.tar.gz .
```

---

## 🎯 Quick Decision Tree

**Need to run quick test?**
→ Use Module 1 (Basic GPU)

**Need job scheduling?**
→ Use Module 2 (SLURM)

**Need multi-GPU training?**
→ Use Module 3 (Parallel)

**Need to compare GPUs?**
→ Use Module 4 (Benchmarking)

**Need to trace GPU operations?**
→ Use eBPF Quick Start

**Finished for the day?**
→ Run `terraform destroy`!

---

**Print this and keep it handy! Good luck, Noah! 🚀**
