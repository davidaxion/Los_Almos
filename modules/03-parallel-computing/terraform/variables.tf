variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "parallel-gpu"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type with GPU"
  type        = string
  default     = "g4dn.2xlarge"  # 1x T4 GPU, 8 vCPUs, 32GB RAM

  validation {
    condition     = can(regex("^(g4dn|g5|g6|p3|p4)", var.instance_type))
    error_message = "Instance type must be a GPU instance (g4dn, g5, g6, p3, p4)."
  }
}

variable "num_nodes" {
  description = "Number of GPU nodes for distributed training"
  type        = number
  default     = 2

  validation {
    condition     = var.num_nodes >= 2 && var.num_nodes <= 8
    error_message = "Number of nodes must be between 2 and 8."
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
