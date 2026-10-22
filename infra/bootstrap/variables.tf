variable "region" {
  description = "Region for the state bucket and IAM resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "allowed_account_ids" {
  description = "Account IDs this bootstrap may run against."
  type        = list(string)
}

variable "state_bucket_name" {
  description = "Globally unique name of the Terraform state bucket."
  type        = string
}

variable "create_dynamodb_lock_table" {
  description = "Also create a DynamoDB lock table (only needed for Terraform < 1.10 or tooling that requires it)."
  type        = bool
  default     = false
}

variable "create_autoscaling_service_linked_role" {
  description = "Create AWSServiceRoleForAutoScaling. Set false if the account already has it (it exists once any Auto Scaling group has been created)."
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if the account already has one."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_default_branch" {
  description = "Branch whose pushes may run plan."
  type        = string
  default     = "main"
}

variable "environments" {
  description = "GitHub Environment names allowed to assume the apply role."
  type        = list(string)
  default     = ["dev", "test", "lifetime", "prod"]
}

variable "role_name_prefix" {
  description = "Prefix for the CI IAM role names."
  type        = string
  default     = "outsystems-terraform"
}

variable "apply_role_policy_arns" {
  description = "Managed policies for the apply role. AdministratorAccess is the pragmatic default; replace it with a scoped policy once the resource set is stable."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
