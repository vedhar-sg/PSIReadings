data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

data "aws_iam_policy_document" "dr_key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" resource refers to this key only
  #checkov:skip=CKV_AWS_111:Key policy; "*" resource refers to this key only
  #checkov:skip=CKV_AWS_356:Key policy; "*" resource refers to this key only
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

# ---------------------------------------------------------------------------
# Primary-region vault, plan and tag-based selection
# ---------------------------------------------------------------------------

resource "aws_backup_vault" "this" {
  name          = var.name
  kms_key_arn   = var.kms_key_arn
  force_destroy = var.force_destroy
}

# Cross-region copies need a vault (and key) in the DR region.
resource "aws_kms_key" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  description             = "OutSystems ${var.name}: cross-region backup copies"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.dr_key.json
}

resource "aws_backup_vault" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name          = "${var.name}-dr"
  kms_key_arn   = aws_kms_key.dr[0].arn
  force_destroy = var.force_destroy
}

resource "aws_backup_plan" "this" {
  name = var.name

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.schedule
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.retention_days
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []
      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn
        lifecycle {
          delete_after = var.dr_retention_days
        }
      }
    }
  }
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_backup_selection" "this" {
  name         = var.name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.selection_tag_key
    value = var.selection_tag_value
  }
}
