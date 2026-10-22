variable "name" {
  description = "Name prefix (e.g. os11-prod)."
  type        = string
}

# --- Network -----------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (ALB egress scope)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for an internet-facing ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for instances (and an internal ALB)."
  type        = list(string)
}

# --- Load balancer -----------------------------------------------------------

variable "alb_internal" {
  description = "Make the ALB internal (reachable only from the VPC / connected networks)."
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "Client CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener."
  type        = string
}

variable "ssl_policy" {
  description = "ALB TLS policy."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_waf" {
  description = "Associate waf_acl_arn with the ALB."
  type        = bool
  default     = true
}

variable "waf_acl_arn" {
  description = "WAFv2 web ACL ARN."
  type        = string
  default     = null
}

variable "target_protocol" {
  description = "Protocol from the ALB to IIS (HTTPS needs a certificate bound in IIS; self-signed is fine)."
  type        = string
  default     = "HTTPS"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_protocol)
    error_message = "target_protocol must be HTTP or HTTPS."
  }
}

variable "health_check_path" {
  description = "Target health check path. Point it at a lightweight page of a deployed module once one exists."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP codes treated as healthy."
  type        = string
  default     = "200-399"
}

variable "enable_stickiness" {
  description = "Enable ALB cookie stickiness (useful for Traditional Web apps)."
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds (long-running Service Center publishes benefit from a higher value)."
  type        = number
  default     = 300
}

variable "alb_deletion_protection" {
  description = "Protect the ALB from deletion."
  type        = bool
  default     = false
}

variable "alb_log_retention_days" {
  description = "Days to keep ALB access logs."
  type        = number
  default     = 90
}

variable "force_destroy_log_bucket" {
  description = "Allow destroying the ALB log bucket while it still holds logs."
  type        = bool
  default     = false
}

# --- Instances ---------------------------------------------------------------

variable "ami_id" {
  description = "AMI for the controller (and front-ends unless frontend_ami_id is set). Null uses the latest Windows Server 2022 base AMI."
  type        = string
  default     = null
}

variable "frontend_ami_id" {
  description = "Golden AMI for front-ends with Platform Server pre-installed. Null falls back to ami_id."
  type        = string
  default     = null
}

variable "controller_instance_type" {
  description = "Controller instance type."
  type        = string
}

variable "frontend_instance_type" {
  description = "Front-end instance type."
  type        = string
}

variable "root_volume_size_gb" {
  description = "Root (C:) volume size."
  type        = number
  default     = 150
}

variable "instance_profile_name" {
  description = "IAM instance profile for all platform servers."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for EBS volumes."
  type        = string
}

variable "termination_protection" {
  description = "Enable EC2 termination protection on the controller."
  type        = bool
  default     = false
}

variable "controller_serves_traffic" {
  description = "Register the controller in the ALB target group (single-server environments such as LifeTime or a small Dev)."
  type        = bool
  default     = false
}

variable "controller_backup_tags" {
  description = "Tags that select the controller for AWS Backup."
  type        = map(string)
  default     = {}
}

variable "instance_tags" {
  description = "Extra tags for instances and volumes."
  type        = map(string)
  default     = {}
}

variable "database_address" {
  description = "Database host, written to the bootstrap environment file."
  type        = string
}

variable "database_port" {
  description = "Database port."
  type        = number
}

variable "secret_arns" {
  description = "Secret ARNs (not values) written to the bootstrap environment file."
  type        = map(string)
  default     = {}
}

# --- Auto Scaling ------------------------------------------------------------

variable "frontend_min_size" {
  description = "Minimum front-ends."
  type        = number
}

variable "frontend_max_size" {
  description = "Maximum front-ends."
  type        = number
}

variable "frontend_desired_capacity" {
  description = "Initial front-end count (later managed by scaling policies)."
  type        = number
}

variable "cpu_target_percent" {
  description = "Target average CPU for the front-end group."
  type        = number
  default     = 60
}

variable "requests_per_target" {
  description = "Target ALB requests per front-end per minute."
  type        = number
  default     = 1000
}

variable "allow_scale_in" {
  description = "Let scaling policies remove front-ends. Keep false until removal is automated (a front-end must also be disabled in Service Center)."
  type        = bool
  default     = false
}

variable "protect_from_scale_in" {
  description = "Set scale-in protection on new front-end instances."
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Seconds before a new front-end is health-checked."
  type        = number
  default     = 1800
}

variable "enable_launch_lifecycle_hook" {
  description = "Hold new front-ends in Pending:Wait until the bootstrap script signals CONTINUE (requires setup.ps1 in a golden AMI)."
  type        = bool
  default     = false
}

variable "lifecycle_hook_timeout" {
  description = "Seconds the launch lifecycle hook waits before abandoning the instance."
  type        = number
  default     = 3600
}
