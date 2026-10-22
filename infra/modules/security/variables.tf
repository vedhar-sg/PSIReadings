variable "name" {
  description = "Name prefix (e.g. os11-prod)."
  type        = string
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the KMS key is deleted after a destroy."
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Recovery window for deleted secrets (0 deletes immediately; use 0 only in throwaway environments)."
  type        = number
  default     = 30
}

variable "installer_bucket_arn" {
  description = "Optional ARN of an S3 bucket holding the OutSystems installers the instances may read."
  type        = string
  default     = null
}

variable "extra_readable_secret_arns" {
  description = "Additional secret ARNs the platform servers may read (e.g. the RDS-managed master secret)."
  type        = list(string)
  default     = []
}
