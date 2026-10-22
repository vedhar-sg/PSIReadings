output "vault_name" {
  description = "Primary backup vault."
  value       = aws_backup_vault.this.name
}

output "dr_vault_arn" {
  description = "DR-region vault ARN (null when cross-region copy is off)."
  value       = var.enable_cross_region_copy ? aws_backup_vault.dr[0].arn : null
}

output "plan_id" {
  description = "Backup plan ID."
  value       = aws_backup_plan.this.id
}
