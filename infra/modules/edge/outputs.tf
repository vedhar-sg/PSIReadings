output "certificate_arn" {
  description = "Validated ACM certificate ARN for the ALB HTTPS listener."
  value       = local.create_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.certificate_arn
}

output "web_acl_arn" {
  description = "WAFv2 web ACL ARN (null when WAF is disabled)."
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}
