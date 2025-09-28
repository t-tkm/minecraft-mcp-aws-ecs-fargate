variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "task_name" {
  description = "Name of the ECS task"
  type        = string
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "minecraft"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cpu" {
  description = "CPU units for the task"
  type        = number
}

variable "memory" {
  description = "Memory for the task"
  type        = number
}

variable "container_memory" {
  description = "Memory for the container"
  type        = number
}

variable "container_memory_reservation" {
  description = "Memory reservation for the container"
  type        = number
}

variable "java_memory_heap" {
  description = "Java heap memory size"
  type        = string
}

variable "rcon_password" {
  description = "RCON password"
  type        = string
  sensitive   = true
}

variable "efs_file_system_id" {
  description = "EFS file system ID"
  type        = string
}

variable "minecraft_target_group_arn" {
  description = "Minecraft target group ARN"
  type        = string
}

variable "rcon_target_group_arn" {
  description = "RCON target group ARN"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Whether to assign public IP"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 7
}

variable "minecraft_version" {
  description = "Minecraft version"
  type        = string
  default     = "1.21.8"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "docker_image" {
  description = "Docker image URI"
  type        = string
}
