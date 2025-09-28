# =============================================================================
# Backup Module
# =============================================================================

resource "aws_backup_vault" "minecraft" {
  name        = "${var.project_name}-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = {
    Name        = "${var.project_name}-backup-vault"
    Environment = var.environment
  }
}

resource "aws_kms_key" "backup" {
  description             = "KMS key for Minecraft backup encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-backup-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.project_name}-backup-key"
  target_key_id = aws_kms_key.backup.key_id
}

resource "aws_backup_plan" "minecraft" {
  name = "${var.project_name}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.minecraft.name
    schedule          = "cron(0 2 * * ? *)"  # Daily at 2 AM

    lifecycle {
      cold_storage_after = 30
      delete_after       = 120
    }

    recovery_point_tags = {
      Name        = "${var.project_name}-backup"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-backup-plan"
    Environment = var.environment
  }
}

resource "aws_backup_selection" "minecraft" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.project_name}-backup-selection"
  plan_id      = aws_backup_plan.minecraft.id

  resources = [
    var.efs_file_system_arn
  ]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backup-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy" "backup" {
  name = "${var.project_name}-backup-policy"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.backup.arn
      }
    ]
  })
}
