output "alb_dns_name" {
  description = "Create a CNAME / alias for the environment host name pointing here."
  value       = module.platform.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (Route 53 alias)."
  value       = module.platform.alb_zone_id
}

output "controller_instance_id" {
  description = "Controller instance (connect with SSM Fleet Manager RDP)."
  value       = module.platform.controller_instance_id
}

output "controller_private_ip" {
  description = "Controller private IP for front-end Configuration Tool setup."
  value       = module.platform.controller_private_ip
}

output "frontend_asg_name" {
  description = "Front-end Auto Scaling group."
  value       = module.platform.frontend_asg_name
}

output "database_address" {
  description = "Database host for the Configuration Tool."
  value       = module.database.address
}

output "database_port" {
  description = "Database port."
  value       = module.database.port
}

output "database_master_secret_arn" {
  description = "RDS-managed master credentials (read them in the console; never copy into code)."
  value       = module.database.master_user_secret_arn
}

output "placeholder_secret_arns" {
  description = "Secrets you must populate yourself before installing OutSystems."
  value       = module.security.secret_arns
}

output "alarm_topic_arn" {
  description = "SNS topic for alarms."
  value       = module.observability.alarm_topic_arn
}

output "nat_public_ips" {
  description = "Outbound IPs of the platform servers (allow-list these at integrations)."
  value       = module.network.nat_public_ips
}
