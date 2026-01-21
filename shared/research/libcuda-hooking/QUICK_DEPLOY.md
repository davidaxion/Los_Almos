# Deploy GPU Research Instance - Quick Start

Complete automated setup of GPU instance with NVIDIA drivers, CUDA, PyTorch, and eBPF tracing tools.

## 🚀 Deploy in 3 Commands

```bash
# 1. Install Terraform (one-time)
brew install terraform awscli
aws configure  # Enter your AWS credentials

# 2. Deploy instance
cd infrastructure
./deploy.sh deploy

# 3. Connect and use
./deploy.sh ssh
```

**That's it!** Instance will be ready in ~10 minutes with everything installed.

## 💰 Cost

- **~$0.52/hour** when running (~$12/day)
- **~$0.10/day** when stopped
- **$0** when destroyed

**Save money:** Stop when not using, destroy when done!

```bash
# AWS Console or CLI
aws ec2 stop-instances --instance-ids <ID>    # Stop (still billed for storage)
./deploy.sh destroy                            # Destroy (remove everything)
```

## 📦 What You Get

Automatically installed:
- ✅ NVIDIA T4 GPU (16GB VRAM)
- ✅ CUDA 12.3 + cuDNN
- ✅ PyTorch 2.x with CUDA
- ✅ Transformers library
- ✅ bpftrace + BCC (eBPF tracing)
- ✅ Helper scripts (gpu-status, quick-trace)
- ✅ All LittleBoy code ready to go

## 🎯 Quick Test

```bash
# SSH into instance
./deploy.sh ssh

# Check GPU
gpu-status

# Run quick trace
sudo quick-trace python3 -c "import torch; print(torch.cuda.is_available())"

# Upload your code
exit
./deploy.sh upload

# Run full test
./deploy.sh ssh
cd ~/littleboy-research/libcuda-hooking/test
sudo ../ebpf/run_trace.sh python simple_inference.py
```

## 📋 Prerequisites

### Before First Deployment

```bash
# 1. Install Terraform
brew install terraform  # macOS
# or: https://www.terraform.io/downloads

# 2. Install AWS CLI
brew install awscli  # macOS
# or: https://aws.amazon.com/cli/

# 3. Configure AWS
aws configure
# Enter:
#   AWS Access Key ID: <your-key>
#   AWS Secret Access Key: <your-secret>
#   Default region: us-west-2
#   Default output format: json

# 4. Verify
aws sts get-caller-identity
```

### Get AWS Credentials

1. Go to AWS Console: https://console.aws.amazon.com
2. Click your name (top right) → Security Credentials
3. Create Access Key → CLI
4. Copy Access Key ID and Secret Access Key
5. Run `aws configure` and paste them

**Or** if you have an IAM user, ask admin for credentials.

## 🎬 Full Workflow

### 1. Deploy

```bash
cd /path/to/LittleBoy/research/libcuda-hooking/infrastructure
./deploy.sh deploy
```

Wait ~10 minutes. Output will show:
```
Instance IP: 54.123.45.67
SSH Command: ssh -i ~/.ssh/littleboy_research ubuntu@54.123.45.67
```

### 2. Monitor Setup (Optional)

```bash
# In another terminal
ssh -i ~/.ssh/littleboy_research ubuntu@54.123.45.67 'tail -f /var/log/cloud-init-output.log'
```

Watch for: "Setup completed at..."

### 3. Verify Setup

```bash
./deploy.sh ssh

# You'll see welcome message:
╔═══════════════════════════════════════════════════════════════╗
║                  LittleBoy Research Instance                  ║
║                 GPU Tracing & Inference Testing               ║
╚═══════════════════════════════════════════════════════════════╝

# Check status
cat SETUP_COMPLETE.txt
gpu-status
```

Expected `gpu-status` output:
```
=== GPU Information ===
Tesla T4 GPU detected
CUDA Version: 12.3

=== PyTorch CUDA Check ===
PyTorch: 2.x.x
CUDA Available: True
Device: Tesla T4
```

### 4. Upload Your Code

```bash
# On your local machine
exit  # Exit SSH
./deploy.sh upload
```

Code will be at: `~/littleboy-research/libcuda-hooking/`

### 5. Run Tests

```bash
./deploy.sh ssh
cd ~/littleboy-research/libcuda-hooking/test

# Simple test
sudo ../ebpf/run_trace.sh python simple_inference.py

# Transformer test
sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py
```

### 6. Analyze Results

```bash
# View traces
ls -lh ~/littleboy-research/traces/

# Quick stats
cat ~/littleboy-research/traces/trace_*.jsonl | grep '^{' | jq -r '.name' | sort | uniq -c

# Visualize
python3 ../tools/visualize_pipeline.py ~/littleboy-research/traces/trace_*.jsonl
```

### 7. Download Results

```bash
# On your local machine
scp -i ~/.ssh/littleboy_research ubuntu@<IP>:~/littleboy-research/traces/* ./local-traces/
```

### 8. Clean Up

```bash
# Stop instance (keeps data, costs ~$0.10/day)
aws ec2 stop-instances --instance-ids <ID>

# Or destroy everything (costs $0)
./deploy.sh destroy
```

## 🔧 Customization

Edit `infrastructure/terraform/terraform.tfvars`:

```hcl
# Use bigger GPU
instance_type = "g5.xlarge"  # A10G instead of T4

# More storage
root_volume_size = 200  # Instead of 150 GB

# Your IP only (recommended for security)
allowed_ssh_cidrs = ["YOUR.IP.HERE/32"]  # Get IP: curl ifconfig.me
```

Apply changes:
```bash
cd terraform
terraform apply
```

## 🐛 Troubleshooting

### Can't SSH

```bash
# Check instance is running
aws ec2 describe-instances --instance-ids <ID>

# Check security group allows your IP
curl ifconfig.me  # Get your current IP
# Edit terraform.tfvars: allowed_ssh_cidrs = ["YOUR.IP/32"]
cd terraform && terraform apply
```

### GPU Not Working

```bash
# Check driver
nvidia-smi

# Reinstall if needed
sudo ubuntu-drivers install --gpgpu
sudo reboot
```

### Setup Not Complete

```bash
# Check progress
tail -f /var/log/cloud-init-output.log

# Setup takes ~10 minutes, be patient!
```

## 📚 Documentation

- **[infrastructure/README.md](infrastructure/README.md)** - Full infrastructure guide
- **[test/RUN_TEST.md](test/RUN_TEST.md)** - Complete testing guide
- **[ebpf/README.md](ebpf/README.md)** - eBPF tracing overview
- **[TESTING_COMPLETE.md](TESTING_COMPLETE.md)** - End-to-end workflow

## 🎯 Next Steps

After deployment:

1. ✅ **Verify GPU**: `gpu-status`
2. ✅ **Test tracing**: `sudo quick-trace python3 -c "import torch; torch.cuda.init()"`
3. ✅ **Upload code**: `./deploy.sh upload`
4. ✅ **Run tests**: See `test/RUN_TEST.md`
5. ✅ **Trace inference**: See `ebpf/README.md`
6. ✅ **Analyze**: See `tools/visualize_pipeline.py --help`
7. ✅ **Research**: Design Little Boy hooks based on findings!

## 💡 Tips

- **Save money**: Always stop/destroy when not using
- **Monitor costs**: AWS Console > Billing Dashboard
- **Set billing alerts**: Avoid surprises
- **Use tmux**: Keep sessions running if disconnected
- **Backup traces**: Download results regularly

## ⚡ TL;DR

```bash
# Install tools (one-time)
brew install terraform awscli && aws configure

# Deploy (~10 min setup)
cd infrastructure && ./deploy.sh deploy

# Connect
./deploy.sh ssh

# Test
gpu-status
sudo quick-trace python3 -c "import torch; print(torch.cuda.is_available())"

# Upload & trace
exit && ./deploy.sh upload
./deploy.sh ssh
cd ~/littleboy-research/libcuda-hooking/test
sudo ../ebpf/run_trace.sh python simple_inference.py

# Clean up
./deploy.sh destroy
```

**Cost**: ~$5 for a full day of research if you remember to stop it!

Ready to trace CUDA! 🚀
