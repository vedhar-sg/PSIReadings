# Unit tests for the platform module (mocked AWS provider, plan only).

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::114774131450:root" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name                      = "os11-test"
  vpc_id                    = "vpc-0123456789abcdef0"
  vpc_cidr                  = "10.99.0.0/16"
  public_subnet_ids         = ["subnet-pub-a", "subnet-pub-b"]
  private_subnet_ids        = ["subnet-prv-a", "subnet-prv-b"]
  certificate_arn           = "arn:aws:acm:ap-southeast-1:111111111111:certificate/test"
  waf_acl_arn               = "arn:aws:wafv2:ap-southeast-1:111111111111:regional/webacl/test/abc"
  controller_instance_type  = "m6i.xlarge"
  frontend_instance_type    = "m6i.large"
  instance_profile_name     = "os11-test-platform-server"
  kms_key_arn               = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
  database_address          = "os11-test.example.rds.amazonaws.com"
  database_port             = 1433
  frontend_min_size         = 2
  frontend_max_size         = 4
  frontend_desired_capacity = 2
}

run "tls_and_redirect" {
  command = plan

  assert {
    condition     = aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.https.protocol == "HTTPS"
    error_message = "HTTPS listener must use the TLS 1.2/1.3 policy."
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "HTTP must redirect to HTTPS."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields
    error_message = "ALB must drop invalid header fields."
  }
}

run "instances_require_imdsv2_and_encrypted_ebs" {
  command = plan

  assert {
    condition     = aws_instance.controller.metadata_options[0].http_tokens == "required" && aws_launch_template.frontend.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required on all platform servers."
  }

  assert {
    condition     = aws_instance.controller.root_block_device[0].encrypted && aws_launch_template.frontend.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "All EBS volumes must be encrypted."
  }

  assert {
    condition     = aws_instance.controller.ami == "ami-0123456789abcdef0"
    error_message = "Without ami_id the latest Windows Server 2022 AMI from SSM must be used."
  }
}

run "outsystems_ports_only_between_roles" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["ctl-12000-from-fe"].from_port == 12000 && aws_vpc_security_group_ingress_rule.this["ctl-5672-from-fe"].from_port == 5672
    error_message = "Controller must accept 12000 and 5672 from front-ends."
  }

  assert {
    condition = alltrue([
      for k, r in aws_vpc_security_group_ingress_rule.this : r.cidr_ipv4 == null if !startswith(k, "alb-")
    ])
    error_message = "Only the ALB may accept CIDR-based ingress; servers accept security-group sources only."
  }

  assert {
    condition     = !contains(keys(aws_vpc_security_group_ingress_rule.this), "ctl-app-from-alb") && length(aws_lb_target_group_attachment.controller) == 0
    error_message = "The controller must not serve app traffic unless controller_serves_traffic is set."
  }
}

run "single_server_environment" {
  command = plan

  variables {
    controller_serves_traffic = true
    frontend_min_size         = 0
    frontend_max_size         = 0
    frontend_desired_capacity = 0
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.controller) == 1 && contains(keys(aws_vpc_security_group_ingress_rule.this), "ctl-app-from-alb")
    error_message = "controller_serves_traffic must register the controller and open the app port from the ALB."
  }

  assert {
    condition     = length(aws_autoscaling_policy.cpu) == 0 && length(aws_autoscaling_policy.requests) == 0
    error_message = "No scaling policies when min == max."
  }
}

run "scale_out_only_by_default" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_policy.cpu) == 1 && aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].disable_scale_in
    error_message = "Scaling policies exist and scale-in is disabled by default."
  }

  assert {
    condition     = aws_autoscaling_group.frontend.health_check_type == "ELB" && aws_autoscaling_group.frontend.health_check_grace_period == 1800
    error_message = "Front-ends use ELB health checks with a long Windows grace period."
  }
}

run "scale_in_opt_in" {
  command = plan

  variables {
    allow_scale_in = true
  }

  assert {
    condition     = !aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].disable_scale_in
    error_message = "allow_scale_in must enable scale-in on the policies."
  }
}

run "internal_alb_uses_private_subnets" {
  command = plan

  variables {
    alb_internal = true
  }

  assert {
    condition     = aws_lb.this.internal && toset(aws_lb.this.subnets) == toset(var.private_subnet_ids)
    error_message = "An internal ALB must be placed in private subnets."
  }
}

run "waf_association_follows_flag" {
  command = plan

  variables {
    enable_waf = false
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No WAF association when enable_waf is false."
  }
}

run "lifecycle_hook_opt_in" {
  command = plan

  variables {
    enable_launch_lifecycle_hook = true
  }

  assert {
    condition     = length(aws_autoscaling_group.frontend.initial_lifecycle_hook) == 1
    error_message = "enable_launch_lifecycle_hook must add the launch hook."
  }
}

run "user_data_template_renders_without_secrets" {
  command = plan

  assert {
    condition = alltrue([
      for hook in [true, false] : (
        strcontains(
          templatefile("templates/user_data.ps1.tftpl", {
            role                  = "frontend", environment = var.name, region = "ap-southeast-1",
            controller_private_ip = "10.0.16.5", database_address = var.database_address, database_port = var.database_port,
            secret_arns_json      = "{}", use_lifecycle_hook = hook,
            asg_name              = "os11-test-frontend", lifecycle_hook_name = "os11-test-frontend-launch"
          }),
          "Complete-ASLifecycleAction"
        ) == hook
      )
    ])
    error_message = "The lifecycle completion call must appear only when the hook is enabled."
  }

  assert {
    condition = !strcontains(lower(templatefile("templates/user_data.ps1.tftpl", {
      role                  = "controller", environment = var.name, region = "ap-southeast-1",
      controller_private_ip = "", database_address = var.database_address, database_port = var.database_port,
      secret_arns_json      = "{}", use_lifecycle_hook = false,
      asg_name              = "x", lifecycle_hook_name = "y"
    })), "password =")
    error_message = "User data must never carry credential values."
  }
}

run "rejects_unknown_target_protocol" {
  command = plan

  variables {
    target_protocol = "TCP"
  }

  expect_failures = [var.target_protocol]
}
