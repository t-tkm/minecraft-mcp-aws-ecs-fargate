variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EFS mount target"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs for EFS"
  type        = list(string)
}

variable "encrypted" {
  description = "Whether EFS is encrypted"
  type        = bool
  default     = true
}

variable "performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
}

variable "transition_to_ia" {
  description = "Transition to IA after days"
  type        = string
  default     = "AFTER_30_DAYS"
}

variable "transition_to_primary_storage_class" {
  description = "Transition to primary storage class after access"
  type        = string
  default     = "AFTER_1_ACCESS"
}

variable "backup_enabled" {
  description = "Enable EFS backup"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}