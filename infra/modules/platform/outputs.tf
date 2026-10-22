output "alb_dns_name" {
  description = "ALB DNS name (point your environment host name at it)."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias records."
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch dimension)."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch dimension)."
  value       = aws_lb_target_group.this.arn_suffix
}

output "frontend_asg_name" {
  description = "Front-end Auto Scaling group name."
  value       = aws_autoscaling_group.frontend.name
}

output "controller_instance_id" {
  description = "Controller EC2 instance ID (connect with SSM Session Manager / Fleet Manager)."
  value       = aws_instance.controller.id
}

output "controller_private_ip" {
  description = "Controller private IP (needed by front-ends in the Configuration Tool)."
  value       = aws_instance.controller.private_ip
}

output "security_group_ids" {
  description = "Security groups by role."
  value = {
    alb        = aws_security_group.alb.id
    frontend   = aws_security_group.frontend.id
    controller = aws_security_group.controller.id
  }
}
