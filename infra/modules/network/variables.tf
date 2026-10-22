variable "name" {
  description = "Name prefix for every network resource (e.g. os11-prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (at least two)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use at least two availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per AZ (ALB and NAT gateways only)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ (Platform Server instances)."
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "One isolated subnet CIDR per AZ (RDS)."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ (cheaper, not AZ-resilient)."
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "Interface VPC endpoint service suffixes to create."
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "secretsmanager", "kms", "logs", "monitoring"]
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the flow-log log group."
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 90
}
