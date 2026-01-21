# Main Terraform configuration for SLURM GPU Testing Environment
# Creates VPC, EC2 instances, EFS, and necessary networking

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

data "aws_caller_identity" "current" {}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "slurm_cluster" {
  name        = "${var.project_name}-slurm-sg"
  description = "Security group for SLURM cluster (SSH, SLURM, Jupyter, custom ports)"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH from allowed CIDR"
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

  # SLURM controller (slurmctld)
  ingress {
    description = "SLURM controller"
    from_port   = 6817
    to_port     = 6817
    protocol    = "tcp"
    self        = true
  }

  # SLURM daemon (slurmd)
  ingress {
    description = "SLURM daemon"
    from_port   = 6818
    to_port     = 6818
    protocol    = "tcp"
    self        = true
  }

  # SLURM database (slurmdbd)
  ingress {
    description = "SLURM database"
    from_port   = 6819
    to_port     = 6819
    protocol    = "tcp"
    self        = true
  }

  # NFS for EFS
  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  # Allow all internal communication
  ingress {
    description = "Internal cluster communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Outbound internet access
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-slurm-sg"
  })
}

# SSH Key Pair
resource "aws_key_pair" "slurm_key" {
  count = var.ssh_key_name == "" ? 1 : 0

  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = merge(var.tags, {
    Name = "${var.project_name}-key"
  })
}

locals {
  ssh_key_name = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.slurm_key[0].key_name
}

# IAM Role for EC2 instances
resource "aws_iam_role" "slurm_node" {
  name = "${var.project_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for S3 and EFS access
resource "aws_iam_role_policy" "slurm_node_policy" {
  name = "${var.project_name}-node-policy"
  role = aws_iam_role.slurm_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_model_bucket}",
          "arn:aws:s3:::${var.s3_model_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeFileSystems"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "slurm_node" {
  name = "${var.project_name}-node-profile"
  role = aws_iam_role.slurm_node.name

  tags = var.tags
}

# Latest Deep Learning AMI (Ubuntu with NVIDIA drivers, CUDA, PyTorch, etc.)
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

# Head Node (SLURM Controller)
resource "aws_instance" "head_node" {
  ami                    = data.aws_ami.deep_learning_ami.id
  instance_type          = var.head_node_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.slurm_cluster.id]
  key_name               = local.ssh_key_name
  iam_instance_profile   = aws_iam_instance_profile.slurm_node.name

  root_block_device {
    volume_size = 100  # GB
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data-head.sh", {
    efs_id            = aws_efs_file_system.models.id
    s3_bucket         = var.s3_model_bucket
    worker_node_count = var.worker_node_count
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-head-node"
    Role = "slurm-controller"
  })
}

# Worker Nodes (SLURM Compute)
resource "aws_instance" "worker_nodes" {
  count = var.worker_node_count

  ami                    = data.aws_ami.deep_learning_ami.id
  instance_type          = var.worker_node_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.slurm_cluster.id]
  key_name               = local.ssh_key_name
  iam_instance_profile   = aws_iam_instance_profile.slurm_node.name

  root_block_device {
    volume_size = 100  # GB
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data-worker.sh", {
    efs_id            = aws_efs_file_system.models.id
    s3_bucket         = var.s3_model_bucket
    head_node_ip      = aws_instance.head_node.private_ip
    worker_index      = count.index
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "slurm-compute"
  })

  depends_on = [aws_instance.head_node]
}
