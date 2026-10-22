variable "name" {
  description = "Name prefix (e.g. os11-prod)."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the primary vault."
  type        = string
}

variable "schedule" {
  description = "Backup schedule (cron, UTC)."
  type        = string
  default     = "cron(0 18 * * ? *)"
}

variable "retention_days" {
  description = "Days to keep recovery points in the primary region."
  type        = number
  default     = 35
}

variable "enable_cross_region_copy" {
  description = "Copy every recovery point to the DR region."
  type        = bool
  default     = false
}

variable "dr_retention_days" {
  description = "Days to keep copies in the DR region."
  type        = number
  default     = 35
}

variable "selection_tag_key" {
  description = "Tag key that selects resources for this plan."
  type        = string
  default     = "BackupPlan"
}

variable "selection_tag_value" {
  description = "Tag value that selects resources for this plan."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroying vaults that still contain recovery points (throwaway environments only)."
  type        = bool
  default     = false
}
