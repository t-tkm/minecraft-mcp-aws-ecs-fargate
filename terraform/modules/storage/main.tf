# =============================================================================
# Storage Module
# =============================================================================

resource "aws_efs_file_system" "minecraft_data" {
  encrypted        = var.encrypted
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }
  lifecycle_policy {
    transition_to_primary_storage_class = var.transition_to_primary_storage_class
  }

  tags = {
    Name        = "${var.project_name}-data"
    Environment = var.environment
  }
}

resource "aws_efs_backup_policy" "minecraft_data_backup_policy" {
  file_system_id = aws_efs_file_system.minecraft_data.id

  backup_policy {
    status = var.backup_enabled ? "ENABLED" : "DISABLED"
  }
}

resource "aws_efs_mount_target" "minecraft_data_mount_target" {
  file_system_id  = aws_efs_file_system.minecraft_data.id
  subnet_id       = var.subnet_id
  security_groups = var.security_group_ids
}
