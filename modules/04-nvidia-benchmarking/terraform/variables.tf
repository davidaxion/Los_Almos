variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "nvidia-benchmark"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type with GPU"
  type        = string
  default     = "g4dn.xlarge"

  validation {
    condition     = can(regex("^(g4dn|g5|g6|p3|p4)", var.instance_type))
    error_message = "Instance type must be a GPU instance (g4dn, g5, g6, p3, p4)."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

# GPU specifications for reference
locals {
  gpu_specs = {
    "g4dn.xlarge"    = { gpu = "T4",      vram_gb = 16,  gpus = 1, cost_per_hour = 0.526 }
    "g4dn.2xlarge"   = { gpu = "T4",      vram_gb = 16,  gpus = 1, cost_per_hour = 0.752 }
    "g6.2xlarge"     = { gpu = "L4",      vram_gb = 24,  gpus = 1, cost_per_hour = 1.10 }
    "g5.xlarge"      = { gpu = "A10G",    vram_gb = 24,  gpus = 1, cost_per_hour = 1.006 }
    "p3.2xlarge"     = { gpu = "V100",    vram_gb = 16,  gpus = 1, cost_per_hour = 3.06 }
    "p4d.24xlarge"   = { gpu = "A100",    vram_gb = 320, gpus = 8, cost_per_hour = 32.77 }
  }

  current_gpu = lookup(local.gpu_specs, var.instance_type, { gpu = "Unknown", vram_gb = 0, gpus = 0, cost_per_hour = 0 })
}
