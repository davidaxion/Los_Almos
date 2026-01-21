# EFS for shared model storage across SLURM cluster nodes

resource "aws_efs_file_system" "models" {
  creation_token   = "${var.project_name}-models-efs"
  performance_mode = var.efs_performance_mode
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-models-efs"
  })
}

# EFS Mount Target
resource "aws_efs_mount_target" "models" {
  file_system_id  = aws_efs_file_system.models.id
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.slurm_cluster.id]
}

# EFS Access Point for models
resource "aws_efs_access_point" "models" {
  file_system_id = aws_efs_file_system.models.id

  root_directory {
    path = "/models"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-models-access-point"
  })
}
