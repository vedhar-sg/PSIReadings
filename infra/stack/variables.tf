# --- Environment identity ----------------------------------------------------

variable "environment" {
  description = "OutSystems environment this state manages."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod", "lifetime"], var.environment)
    error_message = "environment must be dev, test, prod or lifetime."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names (<prefix>-<environment>)."
  type        = string
  default     = "os11"
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "ap-southeast-1"
}

variable "dr_region" {
  description = "Region receiving cross-region backup copies."
  type        = string
  default     = "ap-southeast-2"
}

variable "allowed_account_ids" {
  description = "AWS account IDs this environment may be deployed to (guards against applying to the wrong account)."
  type        = list(string)

  validation {
    condition     = alltrue([for id in var.allowed_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Each account ID must be 12 digits."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

# --- Network -----------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR; must be a /16 for the default subnet layout."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16."
  }
}

variable "az_count" {
  description = "Number of availability zones (2 or 3)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper) instead of one per AZ."
  type        = bool
  default     = true
}

# --- Edge --------------------------------------------------------------------

variable "certificate_arn" {
  description = "Existing ACM certificate ARN. Leave null to issue one for domain_name via Route 53 DNS validation."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Host name of this environment (e.g. dev.apps.example.com)."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Public hosted zone for certificate DNS validation."
  type        = string
  default     = null
}

variable "alb_internal" {
  description = "Internal ALB (no internet exposure)."
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "Client CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_waf" {
  description = "Attach a WAFv2 web ACL to the ALB."
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "count or block."
  type        = string
  default     = "count"
}

variable "target_protocol" {
  description = "ALB-to-IIS protocol: HTTPS (IIS needs a certificate; self-signed is fine) or HTTP."
  type        = string
  default     = "HTTPS"
}

variable "health_check_path" {
  description = "ALB target health check path."
  type        = string
  default     = "/"
}

variable "enable_stickiness" {
  description = "ALB cookie stickiness."
  type        = bool
  default     = false
}

# --- Platform servers --------------------------------------------------------

variable "ami_id" {
  description = "Base AMI. Null uses the latest Windows Server 2022 base image."
  type        = string
  default     = null
}

variable "frontend_ami_id" {
  description = "Golden front-end AMI with Platform Server pre-installed."
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
  description = "C: drive size."
  type        = number
  default     = 150
}

variable "controller_serves_traffic" {
  description = "Put the controller behind the ALB too (single-server environments)."
  type        = bool
  default     = false
}

variable "frontend_min_size" {
  description = "Minimum front-ends."
  type        = number
}

variable "frontend_max_size" {
  description = "Maximum front-ends."
  type        = number
}

variable "frontend_desired_capacity" {
  description = "Initial front-end count."
  type        = number
}

variable "allow_scale_in" {
  description = "Allow scaling policies to remove front-ends."
  type        = bool
  default     = false
}

variable "enable_launch_lifecycle_hook" {
  description = "Hold new front-ends until the bootstrap script completes the lifecycle action."
  type        = bool
  default     = false
}

variable "termination_protection" {
  description = "Protect the controller and ALB from deletion and keep log buckets / vaults on destroy."
  type        = bool
  default     = false
}

variable "installer_bucket_arn" {
  description = "Optional S3 bucket holding OutSystems installers the instances may read."
  type        = string
  default     = null
}

variable "extra_readable_secret_arns" {
  description = "Secrets you created yourself (e.g. the shared private.key) that platform servers may read."
  type        = list(string)
  default     = []
}

variable "secret_recovery_window_days" {
  description = "Recovery window for the placeholder secrets."
  type        = number
  default     = 30
}

# --- Database ----------------------------------------------------------------

variable "db_engine" {
  description = "RDS engine (sqlserver-se, sqlserver-ee, sqlserver-web, sqlserver-ex, oracle-se2, oracle-ee)."
  type        = string
  default     = "sqlserver-se"
}

variable "db_engine_version" {
  description = "Engine version prefix (16.00 = SQL Server 2022)."
  type        = string
  default     = "16.00"
}

variable "db_license_model" {
  description = "license-included or bring-your-own-license."
  type        = string
  default     = "license-included"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_allocated_storage_gb" {
  description = "Initial storage."
  type        = number
  default     = 100
}

variable "db_max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling."
  type        = number
  default     = 500
}

variable "db_multi_az" {
  description = "Multi-AZ standby."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "RDS automated backup retention (PITR window)."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "RDS deletion protection (also takes a final snapshot on destroy)."
  type        = bool
  default     = true
}

# --- Observability and backup ------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 90
}

variable "alarm_emails" {
  description = "Alarm notification recipients."
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "AWS Backup retention in the primary region."
  type        = number
  default     = 14
}

variable "enable_cross_region_backup_copy" {
  description = "Copy recovery points to dr_region."
  type        = bool
  default     = false
}

variable "dr_backup_retention_days" {
  description = "Retention of DR-region copies."
  type        = number
  default     = 35
}
