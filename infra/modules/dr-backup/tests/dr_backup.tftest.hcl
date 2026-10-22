# Unit tests for the dr-backup module (mocked AWS providers, plan only).

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

mock_provider "aws" {
  alias = "dr"
}

variables {
  name                = "os11-test"
  kms_key_arn         = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
  selection_tag_value = "os11-test"
}

run "primary_only_by_default" {
  command = plan

  assert {
    condition     = length(aws_backup_vault.dr) == 0 && length(aws_kms_key.dr) == 0
    error_message = "No DR resources unless cross-region copy is enabled."
  }

  assert {
    condition     = length(one(aws_backup_plan.this.rule).copy_action) == 0
    error_message = "No copy action unless cross-region copy is enabled."
  }

  assert {
    condition     = aws_backup_vault.this.kms_key_arn == var.kms_key_arn
    error_message = "Primary vault must use the environment KMS key."
  }
}

run "selects_resources_by_tag" {
  command = plan

  assert {
    condition     = one(aws_backup_selection.this.selection_tag).key == "BackupPlan" && one(aws_backup_selection.this.selection_tag).value == "os11-test"
    error_message = "Backups must select resources by the BackupPlan tag."
  }
}

run "cross_region_copy" {
  command = plan

  variables {
    enable_cross_region_copy = true
    dr_retention_days        = 90
  }

  assert {
    condition     = length(aws_backup_vault.dr) == 1 && aws_kms_key.dr[0].enable_key_rotation
    error_message = "Cross-region copy needs a DR vault with a rotating key."
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).copy_action).lifecycle[0].delete_after == 90
    error_message = "DR copies must use dr_retention_days."
  }
}
