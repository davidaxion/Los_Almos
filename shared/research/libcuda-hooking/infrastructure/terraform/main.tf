terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "LittleBoy"
      Environment = "Research"
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_ami" "ubuntu_gpu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "littleboy_research" {
  key_name   = "littleboy-research-${var.environment}"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name = "LittleBoy Research Key"
  }
}

# Security Group
resource "aws_security_group" "littleboy_research" {
  name        = "littleboy-research-${var.environment}"
  description = "Security group for LittleBoy research instance"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Jupyter notebook (optional)
  ingress {
    description = "Jupyter Notebook"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LittleBoy Research SG"
  }
}

# EC2 Instance
resource "aws_instance" "littleboy_research" {
  ami           = data.aws_ami.ubuntu_gpu.id
  instance_type = var.instance_type

  key_name               = aws_key_pair.littleboy_research.key_name
  vpc_security_group_ids = [aws_security_group.littleboy_research.id]
  subnet_id              = var.subnet_id

  # Root volume - need space for models
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true

    tags = {
      Name = "LittleBoy Research Root Volume"
    }
  }

  # User data for initial setup
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    github_repo_url = var.github_repo_url
    setup_jupyter   = var.setup_jupyter
  })

  # Important for GPU instances
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "LittleBoy Research Instance"
  }

  lifecycle {
    ignore_changes = [
      user_data,
      ami
    ]
  }
}

# Elastic IP (optional but recommended)
resource "aws_eip" "littleboy_research" {
  count    = var.use_elastic_ip ? 1 : 0
  instance = aws_instance.littleboy_research.id
  domain   = "vpc"

  tags = {
    Name = "LittleBoy Research EIP"
  }
}

# Outputs
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.littleboy_research.id
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = var.use_elastic_ip ? aws_eip.littleboy_research[0].public_ip : aws_instance.littleboy_research.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name"
  value       = aws_instance.littleboy_research.public_dns
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${var.use_elastic_ip ? aws_eip.littleboy_research[0].public_ip : aws_instance.littleboy_research.public_ip}"
}

output "jupyter_url" {
  description = "Jupyter notebook URL (if enabled)"
  value       = var.setup_jupyter ? "http://${var.use_elastic_ip ? aws_eip.littleboy_research[0].public_ip : aws_instance.littleboy_research.public_ip}:8888" : "Not enabled"
}

output "setup_complete_check" {
  description = "Command to check if setup is complete"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${var.use_elastic_ip ? aws_eip.littleboy_research[0].public_ip : aws_instance.littleboy_research.public_ip} 'cat /var/log/cloud-init-output.log | tail -50'"
}
