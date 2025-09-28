# =============================================================================
# Minecraft on AWS ECS - Modular Configuration
# =============================================================================

# =============================================================================
# Local Variables
# =============================================================================

locals {
  project_name = var.project_name
  common_tags = {
    Project      = local.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    ResourceType = "minecraft-infrastructure"
    StackName    = "minecraft-terraform-stack"
    CreatedBy    = "minecraft-mcp-project"
  }
}

# =============================================================================
# Networking Module
# =============================================================================

module "networking" {
  source = "./modules/networking"

  project_name       = local.project_name
  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = var.aws_availability_zones
  allowed_ips        = var.allowed_ips
  my_ip              = var.my_ip
  common_tags        = local.common_tags
}

# =============================================================================
# EC2 Proxy Module
# =============================================================================

module "ec2_proxy" {
  source = "./modules/ec2"

  project_name         = local.project_name
  environment          = var.environment
  ssh_public_key_path  = var.ssh_public_key_path
  security_group_id    = module.networking.ec2_proxy_security_group_id
  subnet_id           = module.networking.public_subnet_ids[0]
  common_tags          = local.common_tags
}

# =============================================================================
# Load Balancer Module
# =============================================================================

module "load_balancer" {
  source = "./modules/load-balancer"

  project_name                = local.project_name
  environment                 = var.environment
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = [module.networking.public_subnet_ids[0]]
  internal                   = true
  enable_deletion_protection = var.environment == "prod" ? true : false
  common_tags                = local.common_tags
}

# =============================================================================
# Storage Module
# =============================================================================

module "storage" {
  source = "./modules/storage"

  project_name      = local.project_name
  environment       = var.environment
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_ids = [module.networking.efs_security_group_id]
  common_tags       = local.common_tags
}

# =============================================================================
# ECS Module
# =============================================================================

module "ecs" {
  source = "./modules/ecs"

  project_name                = local.project_name
  environment                 = var.environment
  task_name                  = var.aws_ecs_task_name
  container_name             = "minecraft"
  aws_region                 = var.aws_region
  cpu                        = var.aws_ecs_cluster_cpu
  memory                     = var.aws_ecs_cluster_memory
  container_memory           = var.aws_ecs_container_memory
  container_memory_reservation = var.aws_ecs_container_memory_reservation
  java_memory_heap           = var.aws_ecs_container_java_memory_heap
  rcon_password              = var.rcon_password
  efs_file_system_id         = module.storage.file_system_id
  minecraft_target_group_arn = module.load_balancer.minecraft_target_group_arn
  rcon_target_group_arn      = module.load_balancer.rcon_target_group_arn
  security_group_ids         = [module.networking.minecraft_security_group_id]
  subnet_ids                 = [module.networking.public_subnet_ids[0]]
  assign_public_ip           = true
  log_retention_days         = var.environment == "prod" ? 30 : 7
  minecraft_version          = var.minecraft_version
  docker_image               = var.docker_image
  common_tags                = local.common_tags
}

# =============================================================================
# Monitoring Module
# =============================================================================

module "monitoring" {
  source = "./modules/monitoring"

  project_name     = local.project_name
  environment      = var.environment
  aws_region       = var.aws_region
  cluster_name     = module.ecs.cluster_name
  service_name     = module.ecs.service_name
  enable_dashboard = var.environment == "prod" ? true : false
  enable_alerts    = var.environment == "prod" ? true : false
  common_tags      = local.common_tags
}

# =============================================================================
# Backup Module
# =============================================================================

module "backup" {
  source = "./modules/backup"

  project_name        = local.project_name
  environment         = var.environment
  efs_file_system_arn = module.storage.file_system_arn
  common_tags         = local.common_tags
}

# =============================================================================
# Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.load_balancer.load_balancer_dns_name
}

output "ec2_proxy_instance_id" {
  description = "ID of the EC2 proxy instance"
  value       = module.ec2_proxy.instance_id
}

output "ec2_proxy_public_ip" {
  description = "Public IP of the EC2 proxy instance"
  value       = module.ec2_proxy.public_ip
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = module.storage.file_system_id
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = module.backup.backup_vault_arn
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = module.backup.backup_plan_arn
}