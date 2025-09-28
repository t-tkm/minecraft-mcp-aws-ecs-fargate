output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.minecraft.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.minecraft.dns_name
}

output "minecraft_target_group_arn" {
  description = "ARN of the Minecraft target group"
  value       = aws_lb_target_group.minecraft.arn
}

output "rcon_target_group_arn" {
  description = "ARN of the RCON target group"
  value       = aws_lb_target_group.minecraft_rcon.arn
}
