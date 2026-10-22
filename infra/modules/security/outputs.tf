output "kms_key_arn" {
  description = "ARN of the environment KMS key."
  value       = aws_kms_key.this.arn
}

output "instance_profile_name" {
  description = "Instance profile for Platform Server instances."
  value       = aws_iam_instance_profile.platform.name
}

output "instance_role_name" {
  description = "IAM role behind the instance profile."
  value       = aws_iam_role.platform.name
}

output "secret_arns" {
  description = "Placeholder secrets the operator must populate, keyed by purpose."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}
