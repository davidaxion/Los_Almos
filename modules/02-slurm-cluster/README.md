# Module 2: SLURM Cluster Setup

**Difficulty**: ⭐⭐ Intermediate
**Time**: 1-2 hours
**Cost**: ~$1.50/hour
**Prerequisites**: Module 1 completed, Linux command line, basic job scheduling concepts

## 🎯 Learning Objectives

By the end of this module, you will:
- ✅ Understand job schedulers and resource management
- ✅ Deploy a multi-node SLURM cluster on AWS
- ✅ Submit and manage GPU jobs with SLURM
- ✅ Configure shared storage (EFS) across nodes
- ✅ Run distributed workloads across multiple GPUs
- ✅ Monitor cluster resources and job queues
- ✅ Optimize job scheduling for GPU utilization

## 📚 What You'll Build

A production-ready SLURM cluster with:
- 1x Head Node (controller + GPU)
- 2x Worker Nodes (compute + GPU)
- Shared EFS storage for models (`/efs/models`)
- NVIDIA T4 GPUs on all nodes
- PyTorch, vLLM, Transformers pre-installed
- ModelLoader integration
- Jupyter Lab for development

## 🚀 Quick Start

```bash
# 1. Deploy the cluster
./deploy.sh

# 2. Wait 10-15 minutes for initialization

# 3. SSH into head node (from output)
ssh -i ~/.ssh/id_rsa ubuntu@<HEAD_NODE_IP>

# 4. Verify cluster
sinfo
nvidia-smi

# 5. Submit first job
sbatch /opt/slurm/examples/test-gpu.sh
squeue
```

## 📖 Concepts Covered

### 1. What is SLURM?

**SLURM** (Simple Linux Utility for Resource Management) is a job scheduler that:
- Manages cluster resources (CPUs, GPUs, memory)
- Queues and schedules jobs fairly
- Tracks job history and accounting
- Scales from single node to thousands of nodes

**Why use SLURM?**
- Share GPUs among multiple users
- Run long-running experiments
- Schedule batch jobs overnight
- Manage resource quotas
- Industry standard (used by most HPC centers)

### 2. SLURM Architecture

```
┌────────────────────────────────────────────────┐
│             Head Node (Controller)             │
│  ┌──────────────────────────────────────────┐  │
│  │  slurmctld (controller daemon)           │  │
│  │  - Receives job submissions              │  │
│  │  - Schedules jobs to workers             │  │
│  │  - Monitors cluster state                │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
┌───────▼────────┐           ┌────────▼───────┐
│  Worker Node 1 │           │  Worker Node 2 │
│  ┌──────────┐  │           │  ┌──────────┐  │
│  │ slurmd   │  │           │  │ slurmd   │  │
│  │ (daemon) │  │           │  │ (daemon) │  │
│  └──────────┘  │           │  └──────────┘  │
│  GPU: T4       │           │  GPU: T4       │
└────────────────┘           └────────────────┘
```

### 3. SLURM Components

- **slurmctld**: Controller daemon (runs on head node)
- **slurmd**: Compute daemon (runs on worker nodes)
- **sbatch**: Submit batch jobs
- **srun**: Run interactive jobs
- **squeue**: View job queue
- **sinfo**: View cluster status
- **scancel**: Cancel jobs

### 4. Job Script Anatomy

```bash
#!/bin/bash
#SBATCH --job-name=my-experiment     # Job name
#SBATCH --output=output-%j.out       # Output file (%j = job ID)
#SBATCH --error=error-%j.err         # Error file
#SBATCH --partition=gpu              # Which partition/queue
#SBATCH --nodes=1                    # How many nodes
#SBATCH --ntasks=1                   # How many tasks (processes)
#SBATCH --cpus-per-task=4            # CPUs per task
#SBATCH --gres=gpu:1                 # GPUs per node
#SBATCH --mem=16G                    # Memory per node
#SBATCH --time=01:00:00              # Max runtime (HH:MM:SS)

# Your commands here
python3 train.py
```

### 5. Shared Storage with EFS

All nodes mount `/efs/models`:
- Upload model once, available everywhere
- No need to copy between nodes
- Persistent across instance restarts

```bash
# On any node
ls /efs/models/
# meta-llama-Llama-3.1-70B-Instruct/
# gpt2/
```

## 🛠️ Exercises

### Exercise 1: Submit Your First Job

**File**: Create `hello-slurm.sh`

```bash
#!/bin/bash
#SBATCH --job-name=hello-slurm
#SBATCH --output=/tmp/hello-%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=00:05:00

echo "Hello from SLURM!"
echo "Running on node: $(hostname)"
echo "Job ID: $SLURM_JOB_ID"
nvidia-smi
```

**Submit and monitor**:
```bash
# Submit job
sbatch hello-slurm.sh
# Submitted batch job 1

# Check queue
squeue
# JOBID PARTITION  NAME     USER  ST  TIME  NODES
#     1 gpu        hello... ubuntu R   0:01  1

# View output
cat /tmp/hello-1.out
```

**Learning goals:**
- Write SLURM job scripts
- Submit with sbatch
- Monitor with squeue
- Read job output

---

### Exercise 2: Interactive GPU Session

**File**: None (interactive)

```bash
# Request interactive GPU session
srun --partition=gpu --gres=gpu:1 --pty bash

# Now you have a shell with GPU allocation
nvidia-smi
python3
>>> import torch
>>> torch.cuda.is_available()
>>> exit()

# Exit releases the GPU
exit
```

**Learning goals:**
- Request interactive resources
- Use GPU in real-time
- Understand resource allocation

---

### Exercise 3: Run vLLM Inference Job

**File**: Create `vllm-job.sh`

```bash
#!/bin/bash
#SBATCH --job-name=vllm-inference
#SBATCH --output=/tmp/vllm-%j.out
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --mem=32G
#SBATCH --time=00:30:00

# Run inference
python3 << 'EOF'
from vllm import LLM, SamplingParams

llm = LLM(model="gpt2", gpu_memory_utilization=0.8)
prompts = ["The future of AI is", "GPU computing enables"]
outputs = llm.generate(prompts, SamplingParams(max_tokens=50))

for prompt, output in zip(prompts, outputs):
    print(f"Prompt: {prompt}")
    print(f"Output: {output.outputs[0].text}")
    print("-" * 60)
EOF
```

**Submit**:
```bash
sbatch vllm-job.sh
tail -f /tmp/vllm-*.out
```

**Learning goals:**
- Run inference as batch job
- Use SLURM with vLLM
- View job output
- Understand GPU memory requests

---

### Exercise 4: Multi-Node Job

**File**: Create `multi-node.sh`

```bash
#!/bin/bash
#SBATCH --job-name=multi-node-test
#SBATCH --output=/tmp/multi-node-%j.out
#SBATCH --partition=gpu
#SBATCH --nodes=2                # Use 2 nodes
#SBATCH --ntasks-per-node=1      # 1 task per node
#SBATCH --gres=gpu:1             # 1 GPU per node
#SBATCH --time=00:10:00

# srun executes on all allocated nodes
srun bash -c "echo \"Task \$SLURM_PROCID running on \$(hostname) with GPU:\"; nvidia-smi -L"
```

**Learning goals:**
- Request multiple nodes
- Run distributed commands
- Understand SLURM environment variables
- See multi-node execution

---

### Exercise 5: Job Arrays (Parallel Experiments)

**File**: Create `array-job.sh`

```bash
#!/bin/bash
#SBATCH --job-name=param-sweep
#SBATCH --output=/tmp/sweep-%A-%a.out  # %A = array job ID, %a = task ID
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --array=1-4                    # Run 4 tasks
#SBATCH --time=00:10:00

# Each task gets different SLURM_ARRAY_TASK_ID
LEARNING_RATE=$(awk "BEGIN {print 0.001 * $SLURM_ARRAY_TASK_ID}")

echo "Task $SLURM_ARRAY_TASK_ID: Learning rate = $LEARNING_RATE"
python3 << EOF
print(f"Training with lr={$LEARNING_RATE}")
# Your training code here
EOF
```

**Submit**:
```bash
sbatch array-job.sh
# Submitted batch job 10

squeue
# JOBID  PARTITION  NAME         USER    ST  TIME  NODES
# 10_1   gpu        param-sweep  ubuntu  R   0:01  1
# 10_2   gpu        param-sweep  ubuntu  R   0:01  1
# 10_3   gpu        param-sweep  ubuntu  R   0:01  1
# 10_4   gpu        param-sweep  ubuntu  R   0:01  1
```

**Learning goals:**
- Run parallel parameter sweeps
- Use job arrays
- Manage multiple experiments
- Understand array task IDs

---

## 🎓 Challenges

### Challenge 1: Resource Monitoring
Create a script that monitors cluster utilization every minute and logs:
- GPU utilization per node
- Memory usage
- Job queue depth
- Save to `/tmp/cluster-stats.log`

### Challenge 2: Automatic Checkpointing
Write a job that:
- Trains a small model
- Saves checkpoints every 5 minutes
- Can resume from checkpoint if job is cancelled
- Test by cancelling and resubmitting

### Challenge 3: Multi-GPU Training
Implement distributed data parallel training:
- Use 2 nodes with 1 GPU each
- Train a simple PyTorch model
- Report speedup vs single GPU

## 📊 Performance Baselines

**Expected Results (3-node cluster with T4 GPUs)**:

| Metric | Expected Value |
|--------|---------------|
| Job submission latency | <1 second |
| Node startup time | ~15 minutes |
| GPU job start time | <5 seconds |
| Cluster idle cost | ~$1.50/hour |
| Max concurrent jobs | 3 (one per GPU) |

## 🐛 Troubleshooting

### Job Stuck in Pending State

```bash
# Check why job is pending
squeue -j <job-id> --start

# View detailed job info
scontrol show job <job-id>

# Common reasons:
# - No nodes available (all busy)
# - Requesting too many resources
# - Partition is down
```

### Worker Nodes Not Showing in SLURM

```bash
# On head node
sudo systemctl status slurmctld
sudo tail -f /var/log/slurm/slurmctld.log

# On worker node
sudo systemctl status slurmd
sudo tail -f /var/log/slurm/slurmd.log

# Restart if needed
sudo systemctl restart slurmctld  # Head
sudo systemctl restart slurmd     # Worker
```

### EFS Not Mounted

```bash
# Check mount
df -h | grep efs

# Manual mount (from terraform output)
sudo mount -t nfs4 -o nfsvers=4.1 <EFS_DNS>:/ /efs/models

# Verify
ls /efs/models
```

### Job Failed with OOM

```bash
# Increase memory request
#SBATCH --mem=64G  # Instead of 32G

# Or reduce GPU memory usage in code
llm = LLM(model="gpt2", gpu_memory_utilization=0.7)  # Instead of 0.9
```

## 📚 SLURM Commands Reference

### Job Submission
```bash
sbatch job.sh          # Submit batch job
srun --gres=gpu:1 cmd  # Run interactive command
salloc -N 2            # Allocate nodes (for interactive use)
```

### Monitoring
```bash
squeue                 # View queue
squeue -u $USER        # Your jobs only
sinfo                  # Cluster status
scontrol show node     # Node details
sacct                  # Job accounting/history
```

### Management
```bash
scancel <job-id>       # Cancel job
scancel -u $USER       # Cancel all your jobs
scontrol hold <job-id> # Hold job
scontrol release <id>  # Release held job
```

### Debugging
```bash
scontrol show job <id>         # Job details
scontrol show node <nodename>  # Node details
sinfo -Nel                     # Detailed node info
```

## 💰 Cost Breakdown

| Resource | Type | Cost/Hour | Monthly (24/7) |
|----------|------|-----------|----------------|
| Head Node | g4dn.xlarge | $0.526 | ~$380 |
| Worker 1 | g4dn.xlarge | $0.526 | ~$380 |
| Worker 2 | g4dn.xlarge | $0.526 | ~$380 |
| EFS Storage | 500GB | ~$0.017/hr | ~$12/month |
| **Total** | | **~$1.60/hr** | **~$1,152/month** |

**Cost Optimization:**
- Stop instances when not in use (EFS persists)
- Use Spot Instances for workers (70% savings)
- Reduce worker count during development
- Delete cluster when done: `terraform destroy`

## 🔗 Integration with Research

This module connects with research materials in `shared/research/`:

- **CUDA Hooking**: Trace jobs submitted to SLURM to see GPU operations
  - Run: `LD_PRELOAD=/path/to/hook.so sbatch job.sh`

- **K3s vLLM Tracing**: Compare SLURM scheduling vs Kubernetes
  - Both are resource managers, different approaches

- **eBPF Tracing**: Trace GPU operations across all SLURM nodes
  - See `shared/research/libcuda-hooking/ebpf/`

## ⏭️ Next Steps

After completing this module:

1. **Module 3: Parallel Computing** - Advanced multi-GPU training
2. **Module 4: NVIDIA Benchmarking** - Compare cluster performance
3. **Research**: Apply eBPF tracing to SLURM jobs

## 🧹 Cleanup

```bash
# From your local machine
cd terraform
terraform destroy

# Confirm deletion
# Type 'yes' when prompted

# Verify
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance-state-name,Values=running"
```

**Warning**: This deletes:
- All EC2 instances
- EFS filesystem and all models
- VPC and networking

**Preserved**:
- S3 bucket (models are safe)
- SSH keys

## 📖 Additional Resources

- [SLURM Documentation](https://slurm.schedmd.com/)
- [SLURM Quick Start Guide](https://slurm.schedmd.com/quickstart.html)
- [Job Array Examples](https://slurm.schedmd.com/job_array.html)
- [AWS EFS Documentation](https://docs.aws.amazon.com/efs/)

---

**Ready to build your cluster?** Run `./deploy.sh` to get started! 🚀
