output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.minecraft.arn
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = aws_backup_plan.minecraft.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key for backup encryption"
  value       = aws_kms_key.backup.arn
}
