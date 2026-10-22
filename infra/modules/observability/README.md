# Observability module

Monitoring and operations for one environment.

- **CloudWatch agent** installed and configured through SSM State Manager on instances tagged `OutSystemsEnvironment=<name>`. It collects:
  - Windows event logs;
  - IIS and Platform Server log files;
  - memory, disk and CPU metrics.
- **KMS-encrypted log groups**, plus an encrypted SNS topic with optional email subscriptions.
- **Alarms:**
  - ALB and application 5xx;
  - unhealthy hosts;
  - response time;
  - CPU;
  - controller disk and status;
  - RDS CPU and storage.
- **EC2 auto-recovery** for the controller.
- **Patch Manager:** a daily scan-only compliance association. Installs are done deliberately, per the patching runbook.
- **CloudWatch dashboard.**

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "observability" {
  source = "../modules/observability"

  name                    = "os11-dev"
  kms_key_arn             = module.security.kms_key_arn
  alarm_emails            = ["platform-team@example.com"]
  alb_arn_suffix          = module.platform.alb_arn_suffix
  target_group_arn_suffix = module.platform.target_group_arn_suffix
  frontend_asg_name       = module.platform.frontend_asg_name
  controller_instance_id  = module.platform.controller_instance_id
  db_instance_identifier  = module.database.identifier
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
| [aws_cloudwatch_dashboard.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.controller_recover](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_ssm_association.configure_cw_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.install_cw_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.patch_scan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_parameter.cw_agent_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| alb\_arn\_suffix | ALB ARN suffix. | `string` | n/a | yes |
| controller\_instance\_id | Controller instance ID. | `string` | n/a | yes |
| db\_instance\_identifier | RDS instance identifier. | `string` | n/a | yes |
| frontend\_asg\_name | Front-end Auto Scaling group name. | `string` | n/a | yes |
| kms\_key\_arn | KMS key for log groups and the SNS topic. | `string` | n/a | yes |
| name | Name prefix (e.g. os11-prod). Instances tagged OutSystemsEnvironment=<name> get the CloudWatch agent. | `string` | n/a | yes |
| target\_group\_arn\_suffix | Target group ARN suffix. | `string` | n/a | yes |
| alarm\_emails | Email addresses subscribed to alarm notifications. | `list(string)` | `[]` | no |
| alb\_5xx\_threshold | ALB-generated 5xx per minute before alarming. | `number` | `10` | no |
| cpu\_threshold\_percent | CPU alarm threshold for instances and the database. | `number` | `85` | no |
| db\_free\_storage\_threshold\_gb | Minimum free database storage before alarming. | `number` | `20` | no |
| disk\_free\_threshold\_percent | Minimum free space on C: before alarming. | `number` | `15` | no |
| log\_retention\_days | Retention for instance log groups. | `number` | `90` | no |
| patch\_scan\_schedule | When SSM Patch Manager scans instances for missing patches (scan only, nothing is installed). | `string` | `"cron(0 2 ? * * *)"` | no |
| response\_time\_threshold\_seconds | Average target response time before alarming. | `number` | `3` | no |
| target\_5xx\_threshold | Application 5xx per minute before alarming. | `number` | `25` | no |

## Outputs

| Name | Description |
|------|-------------|
| alarm\_topic\_arn | SNS topic receiving all alarms. |
| dashboard\_name | CloudWatch dashboard name. |
| log\_group\_names | CloudWatch log groups fed by the agent. |
<!-- END_TF_DOCS -->
