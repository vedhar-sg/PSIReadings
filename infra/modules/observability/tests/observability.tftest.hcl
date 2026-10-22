# Unit tests for the observability module (mocked AWS provider, plan only).

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  name                    = "os11-test"
  kms_key_arn             = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
  alb_arn_suffix          = "app/os11-test/0123456789abcdef"
  target_group_arn_suffix = "targetgroup/os11-test-fe/0123456789abcdef"
  frontend_asg_name       = "os11-test-frontend"
  controller_instance_id  = "i-0123456789abcdef0"
  db_instance_identifier  = "os11-test"
  alarm_emails            = ["ops@example.com", "dba@example.com"]
}

run "core_alarms_exist_and_notify" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["alb-5xx", "target-5xx", "unhealthy-hosts", "controller-disk", "db-storage"] : contains(keys(aws_cloudwatch_metric_alarm.this), k)
    ])
    error_message = "Missing a core alarm."
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : length(a.alarm_actions) == 1])
    error_message = "Every alarm must notify the SNS topic."
  }
}

run "controller_auto_recovers" {
  command = plan

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.controller_recover.alarm_actions, "arn:aws:automate:ap-southeast-1:ec2:recover")
    error_message = "The controller must auto-recover on system status check failure."
  }
}

run "agent_targets_environment_tag" {
  command = plan

  assert {
    condition     = aws_ssm_association.install_cw_agent.targets[0].key == "tag:OutSystemsEnvironment" && aws_ssm_association.install_cw_agent.targets[0].values[0] == "os11-test"
    error_message = "The CloudWatch agent must target instances by OutSystemsEnvironment tag."
  }

  assert {
    condition     = jsondecode(aws_ssm_parameter.cw_agent_config.value).logs.logs_collected.files.collect_list[0].log_group_name == "/outsystems/os11-test/iis"
    error_message = "IIS logs must ship to the environment log group."
  }
}

run "patch_scan_is_scheduled" {
  command = plan

  assert {
    condition     = aws_ssm_association.patch_scan.name == "AWS-RunPatchBaseline" && aws_ssm_association.patch_scan.parameters["Operation"] == "Scan"
    error_message = "A scan-only patch baseline association must exist."
  }
}

run "notifications_encrypted_with_one_subscription_per_email" {
  command = plan

  assert {
    condition     = aws_sns_topic.alarms.kms_master_key_id == var.kms_key_arn && length(aws_sns_topic_subscription.email) == 2
    error_message = "SNS topic must be KMS-encrypted with one subscription per email."
  }

  assert {
    condition     = alltrue([for g in aws_cloudwatch_log_group.this : g.kms_key_id == var.kms_key_arn])
    error_message = "All log groups must be encrypted."
  }
}
