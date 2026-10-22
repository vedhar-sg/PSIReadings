data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Created once per account by the bootstrap stack; needed so Auto Scaling
  # can launch front-ends whose EBS volumes use this customer-managed key.
  autoscaling_slr_arn = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  # Placeholder secrets the operator fills in by hand (never via Terraform).
  secret_names = {
    platform_admin = "OutSystems Service Center / LifeTime admin user"
    rabbitmq       = "RabbitMQ user for the Cache Invalidation Service"
    db_admin       = "OutSystems platform database admin user (created by the Configuration Tool)"
    db_runtime     = "OutSystems platform database runtime user"
    db_log         = "OutSystems log database user"
    db_session     = "OutSystems session database user"
  }
}

# ---------------------------------------------------------------------------
# KMS: one customer-managed key per environment
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" resource refers to this key only
  #checkov:skip=CKV_AWS_111:Key policy; "*" resource refers to this key only
  #checkov:skip=CKV_AWS_356:Key policy; "*" resource refers to this key only
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToEncryptedSns"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }

  statement {
    sid = "AutoScalingEbsUse"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.autoscaling_slr_arn]
    }
  }

  statement {
    sid       = "AutoScalingEbsGrants"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.autoscaling_slr_arn]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "OutSystems ${var.name}: EBS, RDS, Secrets Manager, logs, backups"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# Secrets Manager placeholders: created empty, values set by the operator
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_names

  name                    = "${var.name}/outsystems/${replace(each.key, "_", "-")}"
  description             = "${each.value}. Value is set manually by the operator, never by Terraform."
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = var.secret_recovery_window_days
}

# ---------------------------------------------------------------------------
# IAM: instance profile shared by the controller and front-ends
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "platform" {
  name               = "${var.name}-platform-server"
  description        = "OutSystems Platform Server instances (${var.name})"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.platform.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.platform.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "platform" {
  statement {
    sid       = "ReadOwnEnvironmentSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat([for s in aws_secretsmanager_secret.this : s.arn], var.extra_readable_secret_arns)
  }

  statement {
    sid       = "UseEnvironmentKey"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid       = "AutoScalingLifecycle"
    actions   = ["autoscaling:CompleteLifecycleAction"]
    resources = ["arn:${local.partition}:autoscaling:${local.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.name}-frontend"]
  }

  dynamic "statement" {
    for_each = var.installer_bucket_arn == null ? [] : [var.installer_bucket_arn]
    content {
      sid       = "ReadInstallers"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = [statement.value, "${statement.value}/*"]
    }
  }
}

resource "aws_iam_role_policy" "platform" {
  name   = "outsystems-platform"
  role   = aws_iam_role.platform.id
  policy = data.aws_iam_policy_document.platform.json
}

resource "aws_iam_instance_profile" "platform" {
  name = "${var.name}-platform-server"
  role = aws_iam_role.platform.name
}
