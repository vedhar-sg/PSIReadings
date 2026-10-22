# Unit tests for the account bootstrap (mocked AWS provider, plan only).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  allowed_account_ids = ["111111111111"]
  state_bucket_name   = "example-outsystems-tfstate"
  github_repository   = "example-org/example-repo"
}

run "state_bucket_is_versioned_encrypted_private" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State bucket must be versioned."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "State bucket must use SSE-KMS."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "State bucket must block all public access."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation
    error_message = "State key must rotate."
  }
}

run "native_locking_by_default" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table.lock) == 0
    error_message = "No DynamoDB table unless requested (S3 native locking is the default)."
  }
}

run "optional_dynamodb_lock_table" {
  command = plan

  variables {
    create_dynamodb_lock_table = true
  }

  assert {
    condition     = aws_dynamodb_table.lock[0].hash_key == "LockID" && aws_dynamodb_table.lock[0].point_in_time_recovery[0].enabled
    error_message = "Lock table must use LockID and have point-in-time recovery."
  }
}

run "ci_roles_and_oidc" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "GitHub OIDC provider must be created by default."
  }

  assert {
    condition     = aws_iam_role.plan.name == "outsystems-terraform-plan" && aws_iam_role.apply.name == "outsystems-terraform-apply"
    error_message = "Unexpected CI role names."
  }
}

run "reuse_existing_account_resources" {
  command = plan

  variables {
    create_github_oidc_provider            = false
    create_autoscaling_service_linked_role = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && length(aws_iam_service_linked_role.autoscaling) == 0
    error_message = "Existing OIDC provider / service-linked role must be reusable."
  }
}

run "rejects_malformed_repository" {
  command = plan

  variables {
    github_repository = "not-a-repo"
  }

  expect_failures = [var.github_repository]
}
