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
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
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

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group
resource "aws_security_group" "distributed_training" {
  name        = "${var.project_name}-sg"
  description = "Security group for distributed GPU training"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # PyTorch distributed communication
  ingress {
    from_port   = 29500
    to_port     = 29500
    protocol    = "tcp"
    self        = true
  }

  # NCCL communication (all ports between instances)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# SSH Key Pair
locals {
  ssh_key_name = "${var.project_name}-key"
}

resource "aws_key_pair" "deployer" {
  key_name   = local.ssh_key_name
  public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
}

# GPU Instances for distributed training
resource "aws_instance" "gpu_node" {
  count = var.num_nodes

  ami                    = data.aws_ami.deep_learning_ami.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.distributed_training.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    node_index   = count.index
    project_name = var.project_name
  })

  tags = {
    Name  = "${var.project_name}-node-${count.index}"
    Role  = "gpu-training"
    Index = count.index
  }
}
