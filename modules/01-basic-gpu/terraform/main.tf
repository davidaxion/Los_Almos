# Module 1: Basic GPU Setup - Single GPU Instance
# Simple configuration for learning GPU basics

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
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Deep Learning AMI with NVIDIA drivers
data "aws_ami" "deep_learning_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 20.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Default VPC (simplifies setup for beginners)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "gpu_instance" {
  name        = "${var.project_name}-sg"
  description = "Security group for basic GPU instance (SSH + Jupyter)"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Jupyter Lab
  ingress {
    description = "Jupyter Lab"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Outbound internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-sg"
  })
}

# SSH Key
resource "aws_key_pair" "gpu_key" {
  count      = var.ssh_key_name == "" ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = var.tags
}

locals {
  ssh_key_name = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_key[0].key_name
}

# GPU Instance
resource "aws_instance" "gpu_instance" {
  ami                    = data.aws_ami.deep_learning_ami.id
  instance_type          = var.instance_type
  key_name               = local.ssh_key_name
  vpc_security_group_ids = [aws_security_group.gpu_instance.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    project_name = var.project_name
  })

  tags = merge(var.tags, {
    Name   = "${var.project_name}-instance"
    Module = "01-basic-gpu"
  })
}
