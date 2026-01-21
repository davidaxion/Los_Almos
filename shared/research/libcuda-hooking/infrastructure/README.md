# LittleBoy Research Instance - Infrastructure

One-command deployment of GPU research instance with NVIDIA drivers, CUDA, PyTorch, eBPF tracing tools, and all LittleBoy code ready to go.

## 🚀 Quick Start (3 Steps)

### 1. Install Prerequisites

```bash
# Install Terraform
brew install terraform  # macOS
# Or download from: https://www.terraform.io/downloads

# Install AWS CLI (optional but recommended)
brew install awscli  # macOS
# Or: https://aws.amazon.com/cli/

# Configure AWS credentials
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (us-west-2)
```

### 2. Deploy Instance

```bash
cd infrastructure

# One command - deploys everything!
./deploy.sh deploy
```

That's it! The script will:
- Generate SSH keys
- Create terraform.tfvars with your IP
- Deploy AWS EC2 g4dn.xlarge instance (T4 GPU)
- Install NVIDIA drivers, CUDA, PyTorch
- Install eBPF tools (bpftrace, BCC)
- Set up tracing environment

### 3. Connect and Use

```bash
# SSH into instance
./deploy.sh ssh

# Or use the command from output:
ssh -i ~/.ssh/littleboy_research ubuntu@<INSTANCE_IP>

# Check GPU status
gpu-status

# Run a quick test
sudo quick-trace python3 -c "import torch; print(torch.cuda.is_available())"
```

## 📦 What Gets Installed

### GPU & CUDA Stack
- ✅ NVIDIA GPU Driver (latest)
- ✅ CUDA Toolkit 12.3
- ✅ cuDNN libraries
- ✅ PyTorch with CUDA 12.1
- ✅ Transformers library

### eBPF Tracing Tools
- ✅ bpftrace (high-level tracing)
- ✅ BCC tools (advanced tracing)
- ✅ Linux kernel headers
- ✅ Python BCC bindings

### Utilities
- ✅ nvtop (GPU monitoring)
- ✅ htop, tmux, vim, git
- ✅ jq, tree, wget, curl
- ✅ Development tools (gcc, make, cmake)

### Helper Scripts
- ✅ `gpu-status` - Show GPU info
- ✅ `quick-trace` - Quick CUDA tracing wrapper
- ✅ Custom MOTD with instructions

## 💰 Cost Estimate

### AWS g4dn.xlarge (Recommended)
- **GPU**: NVIDIA T4 (16GB VRAM)
- **CPU**: 4 vCPUs
- **RAM**: 16 GB
- **Cost**: ~$0.52/hour (~$12/day if left running)
- **Storage**: 150 GB SSD

**Stop when not in use to save money!**

### Other Options

| Instance Type | GPU | vCPUs | RAM | Cost/Hour |
|--------------|-----|-------|-----|-----------|
| g4dn.xlarge | T4 | 4 | 16GB | $0.52 |
| g4dn.2xlarge | T4 | 8 | 32GB | $0.75 |
| g5.xlarge | A10G | 4 | 16GB | $1.01 |
| g5.2xlarge | A10G | 8 | 32GB | $1.21 |

Edit `terraform/terraform.tfvars` to change instance type.

## 🛠️ Commands

### Deployment

```bash
./deploy.sh deploy    # Deploy new instance
./deploy.sh upload    # Upload LittleBoy code to instance
./deploy.sh ssh       # Connect to instance
./deploy.sh status    # Show connection info
./deploy.sh destroy   # Destroy instance (saves money!)
```

### On the Instance

```bash
# Check GPU
gpu-status            # Shows GPU, CUDA, PyTorch info
nvidia-smi            # NVIDIA GPU stats
nvtop                 # GPU monitoring (like htop)

# Quick tracing
sudo quick-trace <command>
# Example:
sudo quick-trace python3 test.py

# Manual tracing
sudo bpftrace script.bt
sudo python3 cuda_tracer.py

# Directories
cd ~/littleboy-research/        # Main workspace
cd ~/littleboy-research/traces/ # Trace outputs
```

## 📁 File Structure

```
infrastructure/
├── README.md                    # This file
├── deploy.sh                    # Main deployment script
│
├── terraform/
│   ├── main.tf                  # Terraform configuration
│   ├── variables.tf             # Variable definitions
│   ├── terraform.tfvars.example # Example configuration
│   ├── cloud-init.yaml          # Instance setup script
│   └── terraform.tfvars         # Your config (auto-created)
│
└── CONNECTION_INFO.txt          # Instance details (auto-created)
```

## 🔧 Customization

### Change Instance Type

Edit `terraform/terraform.tfvars`:

```hcl
instance_type = "g5.xlarge"  # Use A10G instead of T4
```

Then:
```bash
cd terraform
terraform apply
```

### Change Region

```hcl
aws_region = "us-east-1"  # Change from us-west-2
```

**Note:** Check GPU availability in your region!

### Increase Storage

```hcl
root_volume_size = 200  # Increase from 150 GB
```

### Add GitHub Repo

```hcl
github_repo_url = "https://github.com/yourusername/LittleBoy.git"
```

The repo will be cloned to `~/littleboy-research/repo/` on instance startup.

### Enable Jupyter Notebook

```hcl
setup_jupyter = true
```

Access at: `http://<INSTANCE_IP>:8888`

## 🔐 Security

### SSH Access

By default, the deploy script sets SSH access to **your current IP only**.

To change:

```hcl
# terraform/terraform.tfvars
allowed_ssh_cidrs = ["1.2.3.4/32"]  # Replace with your IP
```

**Get your IP**: `curl ifconfig.me`

### SSH Keys

- Auto-generated at: `~/.ssh/littleboy_research`
- Public key uploaded to instance
- Private key stays on your machine

### Firewall

Security group allows:
- Port 22 (SSH) from specified IPs only
- Port 8888 (Jupyter) from specified IPs only (if enabled)
- All outbound traffic

## 📊 Instance Setup Timeline

```
0:00  - Instance launches
0:30  - Cloud-init starts
1:00  - Package updates complete
2:00  - NVIDIA driver installing
4:00  - CUDA toolkit installing
6:00  - Python packages installing
8:00  - eBPF tools installing
9:00  - Final verification
10:00 - Instance reboots
11:00 - READY! ✓
```

**Total: ~10-15 minutes**

Monitor progress:
```bash
ssh -i ~/.ssh/littleboy_research ubuntu@<IP> 'tail -f /var/log/cloud-init-output.log'
```

## 🧪 Testing the Instance

### 1. Check Setup Complete

```bash
ssh -i ~/.ssh/littleboy_research ubuntu@<IP>

# Should see welcome message with instructions

# Check completion
cat SETUP_COMPLETE.txt
```

### 2. Verify GPU

```bash
gpu-status
```

Expected output:
```
=== GPU Information ===
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.xx.xx            Driver Version: 535.xx.xx    CUDA Version: 12.3     |
|-------------------------------+----------------------+----------------------+
|   0  Tesla T4            Off  | 00000000:00:1E.0 Off |                    0 |
...

=== PyTorch CUDA Check ===
PyTorch: 2.x.x
CUDA Available: True
CUDA Version: 12.1
Device: Tesla T4
```

### 3. Run Simple Test

```bash
# Simple PyTorch test
python3 << EOF
import torch
print(f"CUDA Available: {torch.cuda.is_available()}")
print(f"Device: {torch.cuda.get_device_name(0)}")
x = torch.randn(1000, 1000).cuda()
y = torch.matmul(x, x)
print(f"Test passed! Result shape: {y.shape}")
EOF
```

### 4. Test eBPF Tracing

```bash
# Quick trace test
sudo quick-trace python3 -c "import torch; torch.cuda.init()"

# Check trace output
ls -lh ~/littleboy-research/traces/
cat ~/littleboy-research/traces/trace_*.jsonl | head -20
```

### 5. Upload and Run LittleBoy Tests

```bash
# On your local machine
cd infrastructure
./deploy.sh upload

# On instance
cd ~/littleboy-research/libcuda-hooking/test
sudo ../ebpf/run_trace.sh python simple_inference.py
```

## 🐛 Troubleshooting

### Setup Failed

```bash
# Check cloud-init logs
ssh -i ~/.ssh/littleboy_research ubuntu@<IP> 'tail -100 /var/log/cloud-init-output.log'

# Check for errors
ssh -i ~/.ssh/littleboy_research ubuntu@<IP> 'grep -i error /var/log/cloud-init-output.log'
```

### GPU Not Found

```bash
# Check driver
nvidia-smi

# If fails, reinstall driver
sudo ubuntu-drivers install --gpgpu
sudo reboot
```

### CUDA Not Available in PyTorch

```bash
# Check CUDA installation
nvcc --version

# Reinstall PyTorch
pip3 uninstall torch
pip3 install torch --index-url https://download.pytorch.org/whl/cu121
```

### Permission Denied for Tracing

```bash
# Need sudo for eBPF
sudo bpftrace <script>
sudo python3 cuda_tracer.py
```

### Can't SSH

```bash
# Check security group allows your IP
# In AWS Console: EC2 > Security Groups > littleboy-research-*
# Ensure your current IP is in allowed_ssh_cidrs

# Or temporarily allow all (NOT RECOMMENDED for production)
cd terraform
# Edit terraform.tfvars: allowed_ssh_cidrs = ["0.0.0.0/0"]
terraform apply
```

## 💾 Saving Costs

### Stop Instance When Not Using

```bash
# In AWS Console or CLI:
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Restart when needed:
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Cost while stopped: ~$0.10/day (just storage)
```

### Destroy When Done

```bash
./deploy.sh destroy

# This removes EVERYTHING including data!
# Make sure to backup traces/results first
```

### Use Spot Instances (Advanced)

Save ~70% by using spot instances (can be interrupted):

Add to `terraform/main.tf`:
```hcl
instance_market_options {
  market_type = "spot"
  spot_options {
    max_price = "0.20"  # Max price/hour
  }
}
```

## 📤 Transferring Results

### Download Traces

```bash
# From local machine
scp -i ~/.ssh/littleboy_research ubuntu@<IP>:~/littleboy-research/traces/* ./local-traces/
```

### Download All Data

```bash
ssh -i ~/.ssh/littleboy_research ubuntu@<IP> 'tar czf ~/research-backup.tar.gz ~/littleboy-research'
scp -i ~/.ssh/littleboy_research ubuntu@<IP>:~/research-backup.tar.gz ./
```

## 🎯 Next Steps After Deployment

1. **Connect to instance**: `./deploy.sh ssh`
2. **Verify setup**: `gpu-status`
3. **Upload code**: `./deploy.sh upload`
4. **Run tests**: See `test/RUN_TEST.md`
5. **Start tracing**: See `ebpf/README.md`
6. **Analyze results**: See `tools/visualize_pipeline.py`

## 📚 Related Documentation

- `../test/RUN_TEST.md` - How to run inference tests
- `../ebpf/README.md` - eBPF tracing guide
- `../ebpf/KERNEL_HOOKS.md` - Adding kernel-level hooks
- `../TESTING_COMPLETE.md` - Complete testing workflow

## 🆘 Support

### AWS Limits

If deployment fails with quota errors:
1. Go to AWS Console > Service Quotas
2. Request increase for "Running On-Demand G instances"
3. Usually approved in 24 hours

### Alternative Providers

Can't use AWS? Try:
- **Lambda Labs**: GPU cloud, similar pricing
- **Paperspace**: Gradient instances
- **GCP**: Similar Terraform, different provider block
- **Local**: If you have NVIDIA GPU

### Getting Help

1. Check cloud-init logs: `tail -f /var/log/cloud-init-output.log`
2. Verify Terraform state: `cd terraform && terraform show`
3. Check AWS Console for any errors

## 🎓 What You're Getting

After deployment, you have a complete research environment with:

- ✅ **GPU**: NVIDIA T4 with 16GB VRAM
- ✅ **CUDA**: Full toolkit with all libraries
- ✅ **PyTorch**: Latest with CUDA support
- ✅ **eBPF**: bpftrace + BCC for tracing
- ✅ **LittleBoy Code**: All tracing scripts ready
- ✅ **SSH Access**: Secure key-based authentication
- ✅ **Monitoring**: nvtop, nvidia-smi, htop
- ✅ **Helper Scripts**: gpu-status, quick-trace

Total setup time: **~3 minutes of your time, 10 minutes of machine time**

**Cost**: ~$0.50/hour when running, ~$0.10/day when stopped

Ready to trace the complete CUDA pipeline! 🚀
