output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.minecraft_data.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.minecraft_data.arn
}

output "dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.minecraft_data.dns_name
}
