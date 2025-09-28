output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.minecraft.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.minecraft.name
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.minecraft.name
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.minecraft.arn
}
