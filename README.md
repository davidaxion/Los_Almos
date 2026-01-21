# Los Alamos GPU Learning Environments

A modular collection of hands-on GPU computing environments for learning cloud infrastructure, parallel computing, and ML operations.

## 🎯 Project Philosophy

**Learn by doing.** Each module is a self-contained learning environment that teaches specific GPU computing concepts through practical exercises. Deploy, experiment, break things, rebuild, and learn!

## 📚 Learning Modules

### Module 1: Basic GPU Setup
**Time**: 30 minutes | **Cost**: ~$0.50/hour | **Difficulty**: Beginner

Learn the fundamentals of GPU instances on AWS.

**What You'll Learn:**
- Launching GPU EC2 instances
- Installing NVIDIA drivers and CUDA
- Running your first GPU workload
- Using PyTorch and vLLM
- Monitoring GPU utilization

**Use Cases:**
- Understanding GPU basics
- Testing model inference
- Quick experiments
- Individual development

[📖 Module 1 Guide](modules/01-basic-gpu/README.md) | [🚀 Quick Deploy](modules/01-basic-gpu/deploy.sh)

---

### Module 2: SLURM Cluster
**Time**: 2 hours | **Cost**: ~$1.60/hour | **Difficulty**: Intermediate

Build a production-ready job scheduling system for GPU workloads.

**What You'll Learn:**
- SLURM architecture and configuration
- Job scheduling and queue management
- Resource allocation (GPUs, memory, CPUs)
- Batch vs interactive jobs
- Multi-node job management
- Shared storage with EFS

**Use Cases:**
- Team GPU sharing
- Batch job processing
- Research computing
- Cost-effective resource utilization

[📖 Module 2 Guide](modules/02-slurm-cluster/README.md) | [🚀 Quick Deploy](modules/02-slurm-cluster/deploy.sh)

---

### Module 3: Parallel Computing
**Time**: 3 hours | **Cost**: ~$3.20/hour | **Difficulty**: Advanced

Master distributed training and multi-GPU parallelism.

**What You'll Learn:**
- Data parallelism vs model parallelism
- Multi-GPU training with PyTorch DDP
- Tensor parallelism for large models
- Pipeline parallelism
- NCCL communication
- Horovod framework
- Performance profiling and optimization

**Use Cases:**
- Training large models
- Distributed data processing
- Multi-node ML pipelines
- Performance optimization

[📖 Module 3 Guide](modules/03-parallel-computing/README.md) | [🚀 Quick Deploy](modules/03-parallel-computing/deploy.sh)

---

### Module 4: NVIDIA Benchmarking
**Time**: 1 hour | **Cost**: ~$1.10/hour | **Difficulty**: Intermediate

Benchmark and compare GPU performance for ML workloads.

**What You'll Learn:**
- GPU performance metrics
- Using nvidia-smi and DCGM
- Benchmarking inference (vLLM)
- Benchmarking training
- Comparing T4 vs L4 vs A100
- Cost vs performance analysis
- Bottleneck identification

**Use Cases:**
- Instance type selection
- Performance optimization
- Cost analysis
- Hardware planning

[📖 Module 4 Guide](modules/04-nvidia-benchmarking/README.md) | [🚀 Quick Deploy](modules/04-nvidia-benchmarking/deploy.sh)

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install required tools
brew install terraform awscli

# Configure AWS credentials
aws configure

# Verify GPU quota
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-DB2E81BA \
  --region us-west-2
```

### Deploy a Module

Each module has a self-contained deployment:

```bash
# Example: Deploy SLURM cluster
cd modules/02-slurm-cluster
./deploy.sh

# Follow interactive prompts
# Access via SSH when ready
ssh -i ~/.ssh/id_rsa ubuntu@<instance-ip>
```

### Complete a Learning Path

```bash
# Beginner Path (4-5 hours)
./modules/01-basic-gpu/deploy.sh        # Start here
./modules/02-slurm-cluster/deploy.sh    # Then this
./modules/04-nvidia-benchmarking/deploy.sh

# Advanced Path (6-8 hours)
./modules/03-parallel-computing/deploy.sh  # Deep dive
./modules/04-nvidia-benchmarking/deploy.sh # Compare results
```

---

## 📁 Project Structure

```
Los_Alamos/
├── README.md                    # This file
├── modules/                     # Learning modules
│   ├── 01-basic-gpu/           # Single GPU instance
│   │   ├── terraform/          # Infrastructure code
│   │   ├── exercises/          # Hands-on exercises
│   │   ├── scripts/            # Helper scripts
│   │   ├── deploy.sh           # One-command deployment
│   │   └── README.md           # Module documentation
│   ├── 02-slurm-cluster/       # Job scheduling
│   ├── 03-parallel-computing/  # Multi-GPU distributed
│   └── 04-nvidia-benchmarking/ # Performance testing
├── shared/                      # Shared resources
│   ├── scripts/                # Common scripts
│   ├── configs/                # Reusable configs
│   └── examples/               # Code examples
└── aws-k8s-gpu-learning/       # Legacy K8s environment

```

---

## 🎓 Learning Paths

### Path 1: Individual Developer
**Goal**: Learn GPU development on AWS

1. ✅ Module 1: Basic GPU Setup (understand the fundamentals)
2. ✅ Module 4: NVIDIA Benchmarking (choose right instance type)
3. 📝 Start building your project!

**Time**: 2 hours | **Cost**: ~$2-3

---

### Path 2: Research Team
**Goal**: Set up shared GPU infrastructure

1. ✅ Module 1: Basic GPU Setup (learn basics)
2. ✅ Module 2: SLURM Cluster (team collaboration)
3. ✅ Module 4: NVIDIA Benchmarking (optimize costs)

**Time**: 4 hours | **Cost**: ~$5-7

---

### Path 3: ML Engineer
**Goal**: Master distributed training

1. ✅ Module 1: Basic GPU Setup (warmup)
2. ✅ Module 3: Parallel Computing (core skills)
3. ✅ Module 4: NVIDIA Benchmarking (optimization)
4. ✅ Module 2: SLURM Cluster (production deployment)

**Time**: 6-8 hours | **Cost**: ~$10-15

---

## 💡 Module Comparison

| Feature | Basic GPU | SLURM | Parallel | Benchmarking |
|---------|-----------|-------|----------|--------------|
| **Instances** | 1 | 3-5 | 2-4 | 1-2 |
| **GPUs** | 1 | 3-5 | 2-8 | 1-2 |
| **Setup Time** | 10 min | 30 min | 45 min | 15 min |
| **Cost/Hour** | $0.50 | $1.60 | $3.20 | $1.10 |
| **Complexity** | ⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Best For** | Learning | Teams | Training | Analysis |

---

## 🛠️ Common Commands

### Deploy Any Module
```bash
cd modules/<module-name>
./deploy.sh
```

### Check Status
```bash
# AWS resources
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PublicIpAddress]'

# Terraform state
cd modules/<module-name>/terraform
terraform show
```

### Cleanup Module
```bash
cd modules/<module-name>/terraform
terraform destroy

# Verify deletion
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=instance-state-name,Values=running"
```

### Cleanup Everything
```bash
# Destroy all modules
for module in modules/*/terraform; do
  cd "$module"
  terraform destroy -auto-approve
  cd -
done
```

---

## 📊 Cost Tracking

**Estimated costs** (us-west-2, g4dn.xlarge instances):

| Module | Setup | Runtime/Hour | 4-Hour Session |
|--------|-------|--------------|----------------|
| Basic GPU | Free | $0.52 | $2.08 |
| SLURM (3 nodes) | Free | $1.56 | $6.24 |
| Parallel (4 nodes) | Free | $2.08 | $8.32 |
| Benchmarking | Free | $0.52 | $2.08 |

**Cost-Saving Tips:**
- Stop instances when not in use (preserves EFS)
- Use Spot instances (add to terraform)
- Destroy modules after learning
- Upgrade to L4 only when needed

---

## 🔧 Customization

### Change Instance Types

```hcl
# In any module's terraform.tfvars
instance_type = "g6.2xlarge"  # Upgrade to L4 GPU
instance_type = "g5.xlarge"   # Use A10G GPU
```

### Scale Cluster Size

```hcl
# In SLURM or Parallel modules
worker_node_count = 4  # Scale to 4 workers
```

### Use Spot Instances

```hcl
# Add to terraform/main.tf in any module
resource "aws_instance" "spot_instance" {
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.30"  # 50% savings on g4dn.xlarge
    }
  }
}
```

---

## 🎯 Exercises

Each module includes hands-on exercises:

- **Basic GPU**: Run inference, monitor GPUs, test PyTorch
- **SLURM**: Submit jobs, manage queue, configure resources
- **Parallel**: Implement DDP, test scaling, profile performance
- **Benchmarking**: Compare GPUs, analyze costs, optimize configs

See each module's `exercises/` directory for details.

---

## 📚 Additional Resources

### Documentation
- [AWS GPU Instances](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing)
- [NVIDIA GPU Cloud](https://catalog.ngc.nvidia.com/)
- [PyTorch Distributed](https://pytorch.org/tutorials/beginner/dist_overview.html)
- [SLURM Documentation](https://slurm.schedmd.com/)

### Tools
- [nvidia-smi](https://developer.nvidia.com/nvidia-system-management-interface)
- [nvtop](https://github.com/Syllo/nvtop)
- [vLLM](https://docs.vllm.ai/)
- [Horovod](https://horovod.readthedocs.io/)

### Community
- [SLURM Users Mailing List](https://lists.schedmd.com/mailman/listinfo/slurm-users)
- [PyTorch Forums](https://discuss.pytorch.org/)
- [r/MachineLearning](https://reddit.com/r/MachineLearning)

---

## 🤝 Contributing

This is a learning project! Feel free to:
- Add new modules
- Improve exercises
- Fix bugs
- Share your learnings

---

## ⚠️ Important Notes

### Security
- **Change default SSH access**: Restrict `ssh_allowed_cidr` to your IP
- **Rotate credentials**: Don't commit AWS keys
- **Use IAM roles**: Avoid hardcoded credentials
- **Enable CloudTrail**: Audit all API calls

### Cleanup
- **Always destroy resources** when done learning
- **Check for orphaned resources** regularly
- **Monitor costs** in AWS Cost Explorer
- **Set billing alarms** for unexpected charges

### Troubleshooting
- Check `terraform/terraform.tfstate` for deployed resources
- Use `aws ec2 describe-instances` to find instances
- SSH issues? Verify security group rules
- GPU not working? Check NVIDIA driver installation

---

## 📝 License

Educational use - learn, modify, and share!

---

## 🙏 Acknowledgments

Built for the **Project Manhattan** model loader integration project.

**Tools Used:**
- Terraform (infrastructure)
- AWS (cloud provider)
- NVIDIA CUDA (GPU computing)
- SLURM (job scheduling)
- PyTorch (ML framework)

---

**Ready to start learning?** Pick a module and deploy! 🚀

```bash
# Beginner? Start here:
cd modules/01-basic-gpu
./deploy.sh
```
