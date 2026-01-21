output "instance_public_ip" {
  description = "Public IP address of benchmark instance"
  value       = aws_instance.benchmark_gpu.public_ip
}

output "instance_id" {
  description = "Instance ID"
  value       = aws_instance.benchmark_gpu.id
}

output "instance_type" {
  description = "Instance type deployed"
  value       = var.instance_type
}

output "gpu_type" {
  description = "GPU type in this instance"
  value       = local.current_gpu.gpu
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.benchmark_gpu.public_ip}"
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT

╔════════════════════════════════════════════════════════════════╗
║         NVIDIA GPU Benchmarking Environment - Ready! 📊        ║
╚════════════════════════════════════════════════════════════════╝

🖥️  INSTANCE DETAILS
────────────────────────────────────────────────────────────────
Instance Type:  ${var.instance_type}
GPU:            ${local.current_gpu.gpu} (${local.current_gpu.gpus}x ${local.current_gpu.vram_gb}GB VRAM)
Public IP:      ${aws_instance.benchmark_gpu.public_ip}
Cost:           ~$${local.current_gpu.cost_per_hour}/hour (~$${local.current_gpu.cost_per_hour * 24}/day)

🔗 SSH CONNECTION
────────────────────────────────────────────────────────────────
ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.benchmark_gpu.public_ip}

⏱️  WAIT 5-10 MINUTES for initialization to complete

✅ VERIFY SETUP
────────────────────────────────────────────────────────────────
# After SSH:
nvidia-smi                    # Check GPU
cd ~/benchmarks               # View benchmark scripts
ls -la

🚀 RUN BENCHMARKS
────────────────────────────────────────────────────────────────
# Quick test
cd ~/benchmarks
python3 gpu_specs.py          # View GPU specifications
python3 tflops_benchmark.py   # Compute performance

# Full benchmark suite
./run_all_benchmarks.sh

# View results
cat results/benchmark_summary.txt

📊 AVAILABLE BENCHMARKS
────────────────────────────────────────────────────────────────
1. gpu_specs.py              - GPU hardware specifications
2. tflops_benchmark.py       - Raw compute performance
3. vllm_benchmark.py         - Inference throughput
4. batch_optimization.py     - Optimal batch size
5. cost_analysis.py          - Cost per million tokens

🔬 ADVANCED TESTING
────────────────────────────────────────────────────────────────
# Test specific model
python3 vllm_benchmark.py --model gpt2

# Compare batch sizes
python3 batch_optimization.py --model gpt2

# Analyze costs
python3 cost_analysis.py --instance-type ${var.instance_type}

📈 VISUALIZE RESULTS
────────────────────────────────────────────────────────────────
# Generate plots (if matplotlib installed)
python3 visualize_results.py

# Or copy results locally
scp -i ~/.ssh/id_rsa ubuntu@${aws_instance.benchmark_gpu.public_ip}:~/benchmarks/results/*.json .

💡 COMPARE DIFFERENT GPUS
────────────────────────────────────────────────────────────────
1. Run benchmarks on this GPU
2. Save results (automatically saved to results/)
3. Destroy this instance
4. Change instance_type in terraform.tfvars
5. Deploy new GPU type
6. Run benchmarks again
7. Compare results

🧹 CLEANUP (when done)
────────────────────────────────────────────────────────────────
terraform destroy

💰 ESTIMATED TESTING COST
────────────────────────────────────────────────────────────────
1 hour of testing: $${local.current_gpu.cost_per_hour}
Full benchmark suite: ~15-30 minutes (~$${local.current_gpu.cost_per_hour * 0.5})

📚 DOCUMENTATION
────────────────────────────────────────────────────────────────
See module README.md for detailed benchmarking methodology
EOT
}
