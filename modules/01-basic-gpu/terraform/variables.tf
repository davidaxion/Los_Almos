# Variables for Module 1: Basic GPU Setup

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "basic-gpu-learning"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "GPU instance type"
  type        = string
  default     = "g4dn.xlarge"  # T4 GPU, perfect for learning
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH"
  type        = string
  default     = "0.0.0.0/0"  # WARNING: Restrict this to your IP!
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name (leave empty to create new)"
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    Project     = "LosAlamos"
    Module      = "01-basic-gpu"
    Environment = "learning"
    ManagedBy   = "Terraform"
  }
}
