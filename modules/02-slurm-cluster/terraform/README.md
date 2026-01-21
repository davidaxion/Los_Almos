# Los Alamos SLURM GPU Testing Environment - Terraform

This Terraform configuration creates a complete SLURM GPU cluster on AWS for model training and inference experiments.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS VPC (10.0.0.0/16)                  │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐  ┌──────────────┐   │
│  │  Head Node   │────▶│  Worker 1    │  │  Worker 2    │   │
│  │  (Controller)│     │  (Compute)   │  │  (Compute)   │   │
│  │              │     │              │  │              │   │
│  │  - SLURM     │     │  - SLURM     │  │  - SLURM     │   │
│  │  - SSH       │     │  - GPU: T4   │  │  - GPU: T4   │   │
│  │  - Jupyter   │     │              │  │              │   │
│  │  - GPU: T4   │     │              │  │              │   │
│  └──────┬───────┘     └──────┬───────┘  └──────┬───────┘   │
│         │                    │                 │           │
│         └────────────────────┴─────────────────┘           │
│                              │                             │
│                    ┌─────────▼─────────┐                   │
│                    │   EFS (Models)    │                   │
│                    │  /efs/models/     │                   │
│                    └───────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                            │
                    ┌───────▼───────┐
                    │  S3 (Models)  │
                    │   Backup      │
                    └───────────────┘
```

## Features

- **SLURM Job Scheduler**: Submit and manage GPU jobs
- **Shared EFS Storage**: Models accessible from all nodes via `/efs/models`
- **S3 Integration**: Access models from existing S3 bucket
- **GPU Compute**: NVIDIA T4 GPUs on all nodes (upgradable to L4)
- **ML Frameworks**: PyTorch, Transformers, vLLM pre-installed
- **ModelLoader**: Automatic model loading from EFS/S3
- **SSH Access**: Direct SSH to all nodes
- **Jupyter Lab**: Interactive development on head node

## Prerequisites

1. **AWS CLI** configured with credentials
2. **Terraform** >= 1.0
3. **SSH key pair** at `~/.ssh/id_rsa.pub`
4. **AWS Account** with GPU quota (g4dn.xlarge)

## Quick Start

### 1. Configure Variables

Create `terraform.tfvars`:

```hcl
# Basic configuration
project_name  = "los-alamos-testing"
environment   = "dev"
aws_region    = "us-west-2"

# Instance types (upgrade to g6.2xlarge for L4 GPUs)
head_node_instance_type   = "g4dn.xlarge"   # 1x T4 GPU
worker_node_instance_type = "g4dn.xlarge"   # 1x T4 GPU
worker_node_count         = 2               # 2-4 workers

# Security (IMPORTANT: Restrict to your IP!)
ssh_allowed_cidr = "0.0.0.0/0"  # WARNING: Open to all - change this!

# Storage
s3_model_bucket = "littleboy-dev-models-752105082763"  # Existing bucket
```

### 2. Deploy

```bash
cd terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (takes ~10 minutes)
terraform apply

# Save outputs
terraform output -json > cluster-info.json
```

### 3. Connect

```bash
# Get head node IP
HEAD_IP=$(terraform output -raw head_node_public_ip)

# SSH into head node
ssh -i ~/.ssh/id_rsa ubuntu@$HEAD_IP

# Check SLURM status
sinfo

# Check GPUs
nvidia-smi

# Check EFS mount
ls -la /efs/models
```

## Post-Deployment Configuration

### Sync SLURM Config to Workers

Worker nodes need configuration files from the head node:

```bash
# SSH into head node
ssh ubuntu@<HEAD_NODE_IP>

# Get worker IPs
WORKER1=<WORKER_1_PRIVATE_IP>
WORKER2=<WORKER_2_PRIVATE_IP>

# Copy munge key to workers
for WORKER in $WORKER1 $WORKER2; do
  sudo scp /etc/munge/munge.key ubuntu@$WORKER:/tmp/
  ssh ubuntu@$WORKER "sudo mv /tmp/munge.key /etc/munge/ && \
                       sudo chown munge:munge /etc/munge/munge.key && \
                       sudo chmod 400 /etc/munge/munge.key && \
                       sudo systemctl restart munge"
done

# Update slurm.conf with worker nodes
sudo nano /etc/slurm/slurm.conf

# Add worker nodes to config:
# NodeName=worker1 CPUs=4 RealMemory=15000 Gres=gpu:1 State=UNKNOWN
# NodeName=worker2 CPUs=4 RealMemory=15000 Gres=gpu:1 State=UNKNOWN
# PartitionName=gpu Nodes=head-node,worker1,worker2 Default=YES MaxTime=INFINITE State=UP

# Copy slurm.conf to workers
for WORKER in $WORKER1 $WORKER2; do
  sudo scp /etc/slurm/slurm.conf ubuntu@$WORKER:/tmp/
  ssh ubuntu@$WORKER "sudo mv /tmp/slurm.conf /etc/slurm/ && \
                       sudo chown slurm:slurm /etc/slurm/slurm.conf && \
                       sudo systemctl restart slurmd"
done

# Restart SLURM controller
sudo systemctl restart slurmctld

# Verify cluster
sinfo
```

## Usage Examples

### Example 1: Test GPU Job

```bash
# Submit test job
sbatch /opt/slurm/examples/test-gpu.sh

# Check queue
squeue

# View output
cat /tmp/gpu-test-*.out
```

### Example 2: vLLM Inference

```bash
# Ensure models are in /efs/models/
ls -la /efs/models/

# Submit inference job
sbatch /opt/slurm/examples/inference-vllm.sh

# Check results
cat /tmp/vllm-inference-*.out
```

### Example 3: Distributed Training

Create `train-multi-gpu.sh`:

```bash
#!/bin/bash
#SBATCH --job-name=distributed-train
#SBATCH --output=/tmp/distributed-train-%j.out
#SBATCH --error=/tmp/distributed-train-%j.err
#SBATCH --partition=gpu
#SBATCH --nodes=2                # Use 2 nodes
#SBATCH --ntasks-per-node=1      # 1 task per node
#SBATCH --gres=gpu:1             # 1 GPU per node
#SBATCH --time=01:00:00

# Your distributed training script here
srun python3 train.py --distributed
```

Submit:
```bash
sbatch train-multi-gpu.sh
```

### Example 4: Interactive Session

```bash
# Request interactive GPU session
srun --partition=gpu --gres=gpu:1 --pty bash

# Now you have a shell with GPU access
nvidia-smi
python3
>>> import torch
>>> torch.cuda.is_available()
```

### Example 5: Jupyter Lab

```bash
# Start Jupyter on head node
jupyter lab --ip=0.0.0.0 --no-browser

# Access from browser
# http://<HEAD_NODE_IP>:8888
```

## SLURM Commands Reference

### Job Management

```bash
# Submit batch job
sbatch job-script.sh

# Submit interactive job
srun --partition=gpu --gres=gpu:1 --pty bash

# View queue
squeue

# View all jobs
squeue -u $USER

# Cancel job
scancel <job-id>

# Cancel all your jobs
scancel -u $USER

# View job details
scontrol show job <job-id>
```

### Cluster Status

```bash
# View partitions and nodes
sinfo

# View node details
scontrol show node

# View node resources
scontrol show node <node-name>

# Check GPU availability
sinfo -o "%n %G"
```

### Job Script Template

```bash
#!/bin/bash
#SBATCH --job-name=my-job           # Job name
#SBATCH --output=output-%j.out      # Output file (%j = job ID)
#SBATCH --error=error-%j.err        # Error file
#SBATCH --partition=gpu             # Partition name
#SBATCH --nodes=1                   # Number of nodes
#SBATCH --ntasks=1                  # Number of tasks
#SBATCH --cpus-per-task=4           # CPUs per task
#SBATCH --gres=gpu:1                # GPUs per node
#SBATCH --mem=16G                   # Memory per node
#SBATCH --time=01:00:00             # Max runtime (HH:MM:SS)

# Your commands here
echo "Job started on $(hostname)"
nvidia-smi
python3 my_script.py
echo "Job finished"
```

## Model Storage

### Using EFS Models

Models in `/efs/models` are instantly available to all nodes:

```python
from model_loader import ModelLoader

loader = ModelLoader()
model_path = loader.get_model_path("llama-70b")
# Returns: /efs/models/meta-llama-Llama-3.1-70B-Instruct

# Use with vLLM
from vllm import LLM
llm = LLM(model=model_path)
```

### Syncing Models from S3

```bash
# Sync specific model
aws s3 sync s3://littleboy-dev-models-752105082763/models/gpt2 /efs/models/gpt2

# Sync all models
aws s3 sync s3://littleboy-dev-models-752105082763/models /efs/models
```

## Cost Management

**Estimated Costs** (us-west-2):
- Head Node (g4dn.xlarge): ~$0.52/hour
- 2x Workers (g4dn.xlarge): ~$1.04/hour
- EFS Storage: ~$0.30/GB/month
- **Total**: ~$1.56/hour + storage (~$40/month with 500GB models)

**Cost Optimization:**
1. Stop instances when not in use (EFS persists)
2. Use Spot Instances for workers (add to terraform)
3. Delete cluster when done: `terraform destroy`

## Upgrade to L4 GPUs

For better performance, upgrade to g6.2xlarge (L4 GPUs):

```hcl
# terraform.tfvars
head_node_instance_type   = "g6.2xlarge"   # 1x L4 GPU, ~$1.10/hour
worker_node_instance_type = "g6.2xlarge"
```

## Cleanup

```bash
# Destroy entire cluster
terraform destroy

# Warning: This deletes:
# - All EC2 instances
# - EFS filesystem (and all models!)
# - VPC and networking
# - Security groups
#
# It does NOT delete:
# - S3 bucket (models are safe)
# - SSH keys
```

## Troubleshooting

### Worker Nodes Not Appearing in SLURM

```bash
# On head node, check SLURM controller
sudo systemctl status slurmctld

# Check logs
sudo tail -f /var/log/slurm/slurmctld.log

# On worker, check slurmd
sudo systemctl status slurmd
sudo tail -f /var/log/slurm/slurmd.log

# Restart services
sudo systemctl restart slurmctld  # Head node
sudo systemctl restart slurmd     # Worker node
```

### EFS Not Mounting

```bash
# Check EFS security group
# Ensure port 2049 is open between nodes

# Manual mount
sudo mount -t nfs4 -o nfsvers=4.1 <EFS_DNS>:/ /efs/models

# Check mount
df -h | grep efs
```

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Reinstall if needed
sudo apt-get install --reinstall nvidia-driver-<version>

# Check SLURM GPU config
cat /etc/slurm/gres.conf
```

## Advanced Configuration

### Adding More Worker Nodes

```hcl
# terraform.tfvars
worker_node_count = 4  # Scale to 4 workers
```

```bash
terraform apply  # Will add 2 more workers
```

### Using Larger Models

For models >70B, use multi-GPU tensor parallelism:

```bash
#!/bin/bash
#SBATCH --gres=gpu:2  # Request 2 GPUs

python3 -m vllm.entrypoints.openai.api_server \
  --model=/efs/models/llama-70b \
  --tensor-parallel-size=2
```

### Custom AMI

To use a custom AMI instead of Deep Learning AMI:

```hcl
# main.tf
data "aws_ami" "custom_ami" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["my-custom-gpu-ami-*"]
  }
}
```

## Support

For issues or questions:
1. Check logs: `/var/log/slurm/`
2. SLURM documentation: https://slurm.schedmd.com/
3. vLLM docs: https://docs.vllm.ai/
4. ModelLoader docs: `../shared-model-utils/README.md`
