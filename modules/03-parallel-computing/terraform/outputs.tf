output "node_public_ips" {
  description = "Public IP addresses of GPU nodes"
  value       = aws_instance.gpu_node[*].public_ip
}

output "node_private_ips" {
  description = "Private IP addresses of GPU nodes"
  value       = aws_instance.gpu_node[*].private_ip
}

output "master_node_ip" {
  description = "Public IP of master node (node 0)"
  value       = aws_instance.gpu_node[0].public_ip
}

output "master_node_private_ip" {
  description = "Private IP of master node (node 0)"
  value       = aws_instance.gpu_node[0].private_ip
}

output "ssh_commands" {
  description = "SSH commands for each node"
  value = {
    for idx, instance in aws_instance.gpu_node : idx => "ssh -i ~/.ssh/id_rsa ubuntu@${instance.public_ip}"
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT

╔════════════════════════════════════════════════════════════════╗
║         Distributed Training Environment - Ready! 🚀           ║
╚════════════════════════════════════════════════════════════════╝

📍 NODE INFORMATION
────────────────────────────────────────────────────────────────
Master Node (Rank 0):
  Public IP:  ${aws_instance.gpu_node[0].public_ip}
  Private IP: ${aws_instance.gpu_node[0].private_ip}

Worker Node (Rank 1):
  Public IP:  ${aws_instance.gpu_node[1].public_ip}
  Private IP: ${aws_instance.gpu_node[1].private_ip}

🔗 SSH CONNECTIONS
────────────────────────────────────────────────────────────────
# Node 0 (Master)
ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.gpu_node[0].public_ip}

# Node 1 (Worker)
ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.gpu_node[1].public_ip}

⏱️  WAIT 5-10 MINUTES for initialization to complete

✅ VERIFY SETUP
────────────────────────────────────────────────────────────────
# After SSH to any node:
nvidia-smi                    # Verify GPU
python3 -c "import torch; print(torch.cuda.is_available())"
cd ~/examples                 # View example scripts

🚀 RUN DISTRIBUTED TRAINING
────────────────────────────────────────────────────────────────
# Option 1: Automatic (uses SLURM-like launcher)
cd ~/examples
./launch_distributed.sh

# Option 2: Manual (run on EACH node in separate terminals)

# Terminal 1 (Node 0):
ssh ubuntu@${aws_instance.gpu_node[0].public_ip}
cd ~/examples
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=0 \
  --master_addr=${aws_instance.gpu_node[0].private_ip} --master_port=29500 \
  distributed_hello.py

# Terminal 2 (Node 1):
ssh ubuntu@${aws_instance.gpu_node[1].public_ip}
cd ~/examples
torchrun --nproc_per_node=1 --nnodes=2 --node_rank=1 \
  --master_addr=${aws_instance.gpu_node[0].private_ip} --master_port=29500 \
  distributed_hello.py

📊 MONITOR TRAINING
────────────────────────────────────────────────────────────────
# On any node:
watch -n 1 nvidia-smi         # GPU utilization

# Check NCCL communication:
export NCCL_DEBUG=INFO
# Then run training script

🧪 EXAMPLE SCRIPTS
────────────────────────────────────────────────────────────────
~/examples/distributed_hello.py        # Hello world
~/examples/ddp_training.py             # Data parallel training
~/examples/profile_communication.py   # Benchmark NCCL
~/examples/gradient_accumulation.py   # Large batch training

📚 DOCUMENTATION
────────────────────────────────────────────────────────────────
See module README for exercises and challenges.

🧹 CLEANUP (when done)
────────────────────────────────────────────────────────────────
terraform destroy

💰 COST: ~$1.50/hour (${var.num_nodes}x ${var.instance_type})
EOT
}
