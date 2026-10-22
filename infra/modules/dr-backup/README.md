# DR backup module

AWS Backup for the stateful parts of an environment: the controller and the RDS instance.

- **Selection:** resources are picked by tag (`BackupPlan=<name>`). Front-ends are stateless and excluded.
- **Primary vault** encrypted with the environment KMS key, with a daily plan and retention.
- **Optional cross-region copy** to a vault (and KMS key) in the DR region, through the `aws.dr` provider alias.

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "backup" {
  source = "../modules/dr-backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                     = "os11-prod"
  kms_key_arn              = module.security.kms_key_arn
  selection_tag_value      = "os11-prod"
  enable_cross_region_copy = true
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
| aws.dr | >= 6.0, < 7.0 |

## Resources

| Name | Type |
|------|------|
| [aws_backup_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_key.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.backup_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dr_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| kms\_key\_arn | KMS key for the primary vault. | `string` | n/a | yes |
| name | Name prefix (e.g. os11-prod). | `string` | n/a | yes |
| selection\_tag\_value | Tag value that selects resources for this plan. | `string` | n/a | yes |
| dr\_retention\_days | Days to keep copies in the DR region. | `number` | `35` | no |
| enable\_cross\_region\_copy | Copy every recovery point to the DR region. | `bool` | `false` | no |
| force\_destroy | Allow destroying vaults that still contain recovery points (throwaway environments only). | `bool` | `false` | no |
| retention\_days | Days to keep recovery points in the primary region. | `number` | `35` | no |
| schedule | Backup schedule (cron, UTC). | `string` | `"cron(0 18 * * ? *)"` | no |
| selection\_tag\_key | Tag key that selects resources for this plan. | `string` | `"BackupPlan"` | no |

## Outputs

| Name | Description |
|------|-------------|
| dr\_vault\_arn | DR-region vault ARN (null when cross-region copy is off). |
| plan\_id | Backup plan ID. |
| vault\_name | Primary backup vault. |
<!-- END_TF_DOCS -->
