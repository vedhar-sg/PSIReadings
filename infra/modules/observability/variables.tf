variable "name" {
  description = "Name prefix (e.g. os11-prod). Instances tagged OutSystemsEnvironment=<name> get the CloudWatch agent."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for log groups and the SNS topic."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for instance log groups."
  type        = number
  default     = 90
}

variable "alarm_emails" {
  description = "Email addresses subscribed to alarm notifications."
  type        = list(string)
  default     = []
}

variable "patch_scan_schedule" {
  description = "When SSM Patch Manager scans instances for missing patches (scan only, nothing is installed)."
  type        = string
  default     = "cron(0 2 ? * * *)"
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix."
  type        = string
}

variable "frontend_asg_name" {
  description = "Front-end Auto Scaling group name."
  type        = string
}

variable "controller_instance_id" {
  description = "Controller instance ID."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "ALB-generated 5xx per minute before alarming."
  type        = number
  default     = 10
}

variable "target_5xx_threshold" {
  description = "Application 5xx per minute before alarming."
  type        = number
  default     = 25
}

variable "response_time_threshold_seconds" {
  description = "Average target response time before alarming."
  type        = number
  default     = 3
}

variable "cpu_threshold_percent" {
  description = "CPU alarm threshold for instances and the database."
  type        = number
  default     = 85
}

variable "disk_free_threshold_percent" {
  description = "Minimum free space on C: before alarming."
  type        = number
  default     = 15
}

variable "db_free_storage_threshold_gb" {
  description = "Minimum free database storage before alarming."
  type        = number
  default     = 20
}
