output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "minecraft_security_group_id" {
  description = "ID of the Minecraft security group"
  value       = aws_security_group.minecraft.id
}

output "ec2_proxy_security_group_id" {
  description = "ID of the EC2 proxy security group"
  value       = aws_security_group.ec2_proxy.id
}

output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

# Load balancer security group output - REMOVED (not needed for NLB)
