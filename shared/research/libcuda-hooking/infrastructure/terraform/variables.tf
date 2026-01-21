variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-west-2" # Oregon - good GPU availability
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "research"
}

variable "instance_type" {
  description = "EC2 instance type (GPU instance)"
  type        = string
  default     = "g4dn.xlarge" # T4 GPU, 4 vCPUs, 16GB RAM - ~$0.52/hr

  validation {
    condition = can(regex("^g[4-5]", var.instance_type))
    error_message = "Must be a GPU instance (g4dn.* or g5.*)"
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 100 # Need space for models and traces
}

variable "vpc_id" {
  description = "VPC ID (use default VPC if not specified)"
  type        = string
  default     = "" # Will use default VPC
}

variable "subnet_id" {
  description = "Subnet ID (use default subnet if not specified)"
  type        = string
  default     = "" # Will use default subnet
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Change this to your IP!
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/littleboy_research.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/littleboy_research"
}

variable "use_elastic_ip" {
  description = "Whether to use Elastic IP (recommended)"
  type        = bool
  default     = true
}

variable "github_repo_url" {
  description = "GitHub repo URL to clone (optional)"
  type        = string
  default     = ""
}

variable "setup_jupyter" {
  description = "Whether to set up Jupyter notebook"
  type        = bool
  default     = false
}
