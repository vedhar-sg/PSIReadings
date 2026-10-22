output "state_bucket" {
  description = "Put this in envs/<env>/backend.hcl as bucket."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "KMS key encrypting the state bucket."
  value       = aws_kms_key.state.arn
}

output "dynamodb_lock_table" {
  description = "Lock table name (null when not created)."
  value       = var.create_dynamodb_lock_table ? aws_dynamodb_table.lock[0].name : null
}

output "plan_role_arn" {
  description = "Set as the GitHub repository variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as the GitHub environment variable AWS_APPLY_ROLE_ARN in each environment."
  value       = aws_iam_role.apply.arn
}
