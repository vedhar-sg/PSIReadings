# Security module

Per-environment security primitives.

- **Customer-managed KMS key** with rotation. Its key policy also covers:
  - CloudWatch Logs;
  - CloudWatch alarms publishing to an encrypted SNS topic;
  - the Auto Scaling service-linked role, which needs it to launch front-ends with encrypted EBS.
- **Secrets Manager placeholders** for the OutSystems admin, RabbitMQ and database users. They are created **without values**: the operator sets them, never Terraform.
- **IAM role and instance profile** for Platform Server instances:
  - SSM and CloudWatch agent access;
  - read access to this environment's secrets and key only;
  - lifecycle completion for this environment's front-end Auto Scaling group.

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "security" {
  source = "../modules/security"

  name                        = "os11-dev"
  secret_recovery_window_days = 7
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.10 |
| aws | >= 6.0, < 7.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 6.0, < 7.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_instance_profile.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cloudwatch_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ec2_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix (e.g. os11-prod). | `string` | n/a | yes |
| extra\_readable\_secret\_arns | Additional secret ARNs the platform servers may read (e.g. the RDS-managed master secret). | `list(string)` | `[]` | no |
| installer\_bucket\_arn | Optional ARN of an S3 bucket holding the OutSystems installers the instances may read. | `string` | `null` | no |
| kms\_deletion\_window\_days | Waiting period before the KMS key is deleted after a destroy. | `number` | `30` | no |
| secret\_recovery\_window\_days | Recovery window for deleted secrets (0 deletes immediately; use 0 only in throwaway environments). | `number` | `30` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance\_profile\_name | Instance profile for Platform Server instances. |
| instance\_role\_name | IAM role behind the instance profile. |
| kms\_key\_arn | ARN of the environment KMS key. |
| secret\_arns | Placeholder secrets the operator must populate, keyed by purpose. |
<!-- END_TF_DOCS -->
