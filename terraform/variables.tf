# Variables for SLURM GPU Testing Environment
# This Terraform setup creates a simple SLURM cluster for model training/inference

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "los-alamos-testing"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

# Instance configuration
variable "head_node_instance_type" {
  description = "EC2 instance type for SLURM head node (controller)"
  type        = string
  default     = "g4dn.xlarge"  # 1x T4 GPU, 4 vCPUs, 16 GB RAM
}

variable "worker_node_instance_type" {
  description = "EC2 instance type for SLURM worker nodes (compute)"
  type        = string
  default     = "g4dn.xlarge"  # 1x T4 GPU, 4 vCPUs, 16 GB RAM
}

variable "worker_node_count" {
  description = "Number of SLURM worker nodes"
  type        = number
  default     = 2  # Start with 2, can scale to 4
}

# Network configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH (set to your IP for security)"
  type        = string
  default     = "0.0.0.0/0"  # WARNING: Open to all - restrict this in production!
}

# SSH key
variable "ssh_key_name" {
  description = "Name of existing EC2 key pair for SSH access"
  type        = string
  default     = ""  # Will create new key if not specified
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# Storage configuration
variable "efs_performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "s3_model_bucket" {
  description = "S3 bucket name for model storage (leave empty to use existing littleboy bucket)"
  type        = string
  default     = "littleboy-dev-models-752105082763"
}

# Tags
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "LosAlamos"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "SLURM-GPU-Testing"
  }
}
