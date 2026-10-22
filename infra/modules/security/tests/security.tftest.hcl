# Unit tests for the security module (mocked AWS provider, plan only).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name = "os11-test"
}

run "kms_key_rotates" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation
    error_message = "The environment KMS key must have rotation enabled."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/os11-test"
    error_message = "KMS alias must be alias/<name>."
  }
}

run "placeholder_secrets_have_no_values" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.this) == 6
    error_message = "Expected six placeholder secrets."
  }

  assert {
    condition     = alltrue([for s in aws_secretsmanager_secret.this : startswith(s.name, "os11-test/outsystems/")])
    error_message = "Secrets must be namespaced under <name>/outsystems/."
  }

  assert {
    condition     = alltrue([for s in aws_secretsmanager_secret.this : s.recovery_window_in_days == 30])
    error_message = "Default recovery window must be 30 days."
  }
}

run "recovery_window_is_configurable" {
  command = plan

  variables {
    secret_recovery_window_days = 7
  }

  assert {
    condition     = alltrue([for s in aws_secretsmanager_secret.this : s.recovery_window_in_days == 7])
    error_message = "secret_recovery_window_days must be applied to every secret."
  }
}

run "instance_profile_has_ssm_and_cloudwatch" {
  command = plan

  assert {
    condition     = endswith(aws_iam_role_policy_attachment.ssm.policy_arn, "AmazonSSMManagedInstanceCore")
    error_message = "Instances need SSM (no inbound admin ports are opened)."
  }

  assert {
    condition     = endswith(aws_iam_role_policy_attachment.cloudwatch_agent.policy_arn, "CloudWatchAgentServerPolicy")
    error_message = "Instances need the CloudWatch agent policy."
  }

  assert {
    condition     = aws_iam_instance_profile.platform.name == "os11-test-platform-server"
    error_message = "Unexpected instance profile name."
  }
}
