variable "project_name" {
  type        = string
  description = "Name of the project (used for resource naming and tagging)"
  default     = "minecraft-mcp"
}

variable "aws_ecs_task_name" {
  type        = string
  description = "Name of the ECS task"
  default     = "minecraft-on-ecs"
}

variable "aws_ecs_cluster_cpu" {
  type        = number
  description = "CPU units for ECS cluster (1024 = 1 vCPU)"
  default     = 2048
  validation {
    condition     = var.aws_ecs_cluster_cpu >= 1024 && var.aws_ecs_cluster_cpu <= 4096
    error_message = "CPU must be between 1024 and 4096 units."
  }
}

variable "aws_ecs_cluster_memory" {
  type        = number
  description = "Memory for ECS cluster in MB"
  default     = 8192
  validation {
    condition     = var.aws_ecs_cluster_memory >= 2048 && var.aws_ecs_cluster_memory <= 16384
    error_message = "Memory must be between 2048 and 16384 MB."
  }
}

variable "aws_ecs_container_memory" {
  type        = number
  description = "Memory for container in MB"
  default     = 8192
  validation {
    condition     = var.aws_ecs_container_memory >= 2048 && var.aws_ecs_container_memory <= 16384
    error_message = "Container memory must be between 2048 and 16384 MB."
  }
}

variable "aws_ecs_container_memory_reservation" {
  type        = number
  description = "Memory reservation for container in MB"
  default     = 4096
  validation {
    condition     = var.aws_ecs_container_memory_reservation >= 1024
    error_message = "Memory reservation must be at least 1024 MB."
  }
}

variable "aws_ecs_container_java_memory_heap" {
  type        = string
  description = "Java heap memory size (e.g., 6G, 4G)"
  default     = "6G"
  validation {
    condition     = can(regex("^[0-9]+[GM]$", var.aws_ecs_container_java_memory_heap))
    error_message = "Java memory heap must be in format like '6G' or '4096M'."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "aws_availability_zones" {
  type        = list(string)
  description = "List of availability zones"
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
  validation {
    condition     = length(var.aws_availability_zones) >= 1 && length(var.aws_availability_zones) <= 3
    error_message = "Must specify between 1 and 3 availability zones."
  }
}

variable "allowed_ips" {
  type        = list(string)
  description = "List of IP addresses/CIDR blocks allowed to access Minecraft server (Note: This is overridden by My IP restriction in security groups)"
  default     = ["0.0.0.0/0"]  # 注意: セキュリティグループでMy IP制限が適用されます
}

variable "rcon_password" {
  type        = string
  description = "RCON password for Minecraft server (must be at least 8 characters)"
  sensitive   = true
  default     = null
  validation {
    condition     = var.rcon_password == null || var.rcon_password == "" || try(length(var.rcon_password) >= 8, false)
    error_message = "RCON password must be at least 8 characters long."
  }
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key for EC2 proxy"
  default     = "~/.ssh/minecraft-proxy-key.pub"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "minecraft_version" {
  type        = string
  description = "Minecraft version"
  default     = "1.21.8"
}

variable "docker_image" {
  type        = string
  description = "Docker image URI. If ECR repository is specified, use ECR image. Otherwise, use DockerHub image."
  default     = "itzg/minecraft-server:latest"
}

variable "my_ip" {
  type        = string
  description = "Your IP address for security group rules (e.g., 203.0.113.1/32). If empty, will auto-detect current IP"
  default     = ""
}
