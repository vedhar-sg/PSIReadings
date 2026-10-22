output "alarm_topic_arn" {
  description = "SNS topic receiving all alarms."
  value       = aws_sns_topic.alarms.arn
}

output "log_group_names" {
  description = "CloudWatch log groups fed by the agent."
  value       = { for k, g in aws_cloudwatch_log_group.this : k => g.name }
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}
