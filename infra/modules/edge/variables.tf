variable "name" {
  description = "Name prefix (e.g. os11-prod)."
  type        = string
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN for the ALB. When null, a DNS-validated certificate is created for domain_name."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Primary host name of the environment (e.g. apps.example.com). Required when certificate_arn is null."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn != null || (var.domain_name != null && var.route53_zone_id != null)
    error_message = "Set certificate_arn, or set both domain_name and route53_zone_id so a certificate can be issued."
  }
}

variable "subject_alternative_names" {
  description = "Extra host names on the created certificate."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Public hosted zone used for ACM DNS validation."
  type        = string
  default     = null
}

variable "enable_waf" {
  description = "Create a WAFv2 web ACL."
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "count (observe only) or block."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_mode)
    error_message = "waf_mode must be count or block."
  }
}

variable "common_rule_overrides" {
  description = "Rules in AWSManagedRulesCommonRuleSet downgraded to count. SizeRestrictions_BODY would otherwise block solution/module uploads to Service Center and LifeTime."
  type        = list(string)
  default     = ["SizeRestrictions_BODY"]
}

variable "rate_limit_per_5min" {
  description = "Requests per 5 minutes per client IP before the rate rule triggers."
  type        = number
  default     = 2000
}

variable "kms_key_arn" {
  description = "KMS key for the WAF log group."
  type        = string
}

variable "log_retention_days" {
  description = "WAF log retention."
  type        = number
  default     = 90
}
