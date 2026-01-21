# Terraform outputs for easy access to cluster information

output "head_node_public_ip" {
  description = "Public IP address of SLURM head node (controller)"
  value       = aws_instance.head_node.public_ip
}

output "head_node_private_ip" {
  description = "Private IP address of SLURM head node"
  value       = aws_instance.head_node.private_ip
}

output "worker_node_public_ips" {
  description = "Public IP addresses of SLURM worker nodes"
  value       = aws_instance.worker_nodes[*].public_ip
}

output "worker_node_private_ips" {
  description = "Private IP addresses of SLURM worker nodes"
  value       = aws_instance.worker_nodes[*].private_ip
}

output "efs_id" {
  description = "EFS filesystem ID for model storage"
  value       = aws_efs_file_system.models.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.models.dns_name
}

output "s3_model_bucket" {
  description = "S3 bucket name for model storage"
  value       = var.s3_model_bucket
}

output "ssh_connection_command" {
  description = "SSH command to connect to head node"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.head_node.public_ip}"
}

output "jupyter_url" {
  description = "Jupyter Lab URL (if running on head node)"
  value       = "http://${aws_instance.head_node.public_ip}:8888"
}

output "cluster_info" {
  description = "Complete cluster information"
  value = {
    head_node = {
      public_ip  = aws_instance.head_node.public_ip
      private_ip = aws_instance.head_node.private_ip
      instance_type = var.head_node_instance_type
    }
    worker_nodes = [
      for i, instance in aws_instance.worker_nodes : {
        index      = i + 1
        public_ip  = instance.public_ip
        private_ip = instance.private_ip
        instance_type = var.worker_node_instance_type
      }
    ]
    storage = {
      efs_id       = aws_efs_file_system.models.id
      efs_dns      = aws_efs_file_system.models.dns_name
      s3_bucket    = var.s3_model_bucket
    }
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT

  ╔════════════════════════════════════════════════════════════════════════════╗
  ║                   SLURM GPU Cluster Deployed Successfully!                 ║
  ╚════════════════════════════════════════════════════════════════════════════╝

  📡 HEAD NODE (SLURM Controller)
  ─────────────────────────────────────
  Public IP:  ${aws_instance.head_node.public_ip}
  Private IP: ${aws_instance.head_node.private_ip}

  🔗 SSH CONNECTION
  ─────────────────────────────────────
  ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.head_node.public_ip}

  💻 WORKER NODES
  ─────────────────────────────────────
  ${join("\n  ", [for i, ip in aws_instance.worker_nodes[*].public_ip : "Worker ${i + 1}: ${ip}"])}

  📦 STORAGE
  ─────────────────────────────────────
  EFS ID:     ${aws_efs_file_system.models.id}
  S3 Bucket:  ${var.s3_model_bucket}
  Mount Path: /efs/models

  🎯 NEXT STEPS
  ─────────────────────────────────────
  1. SSH into head node (wait 5-10 minutes for initialization)
  2. Check SLURM status: sinfo
  3. Submit test job: sbatch /opt/slurm/examples/test-gpu.sh
  4. View models: ls /efs/models
  5. Start Jupyter: jupyter lab --ip=0.0.0.0

  📚 DOCUMENTATION
  ─────────────────────────────────────
  - SLURM commands: man slurm
  - Submit jobs: sbatch <script>
  - Check queue: squeue
  - Cancel jobs: scancel <job-id>

  🔒 SECURITY NOTE
  ─────────────────────────────────────
  SSH is currently open to ${var.ssh_allowed_cidr}
  Restrict this in production by updating var.ssh_allowed_cidr

  EOT
}
