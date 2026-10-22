# Edge module

TLS certificate and web application firewall for the environment's ALB.

- **Certificate:** an ACM certificate DNS-validated in Route 53. Alternatively, pass an existing `certificate_arn`.
- **WAFv2 web ACL:**
  - AWS managed rule groups: IP reputation, the common rule set, known bad inputs and SQL injection;
  - a per-IP rate limit;
  - `count` (observe) or `block` mode.
- `SizeRestrictions_BODY` is downgraded to `count` by default, so Service Center and LifeTime solution uploads are not blocked.
- **WAF logs** go to a KMS-encrypted log group, `aws-waf-logs-<name>`.

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "edge" {
  source = "../modules/edge"

  name            = "os11-dev"
  domain_name     = "dev.apps.example.com"
  route53_zone_id = "Z0000000000000000000"
  waf_mode        = "count"
  kms_key_arn     = module.security.kms_key_arn
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
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudwatch_log_group.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| kms\_key\_arn | KMS key for the WAF log group. | `string` | n/a | yes |
| name | Name prefix (e.g. os11-prod). | `string` | n/a | yes |
| certificate\_arn | Existing ACM certificate ARN for the ALB. When null, a DNS-validated certificate is created for domain\_name. | `string` | `null` | no |
| common\_rule\_overrides | Rules in AWSManagedRulesCommonRuleSet downgraded to count. SizeRestrictions\_BODY would otherwise block solution/module uploads to Service Center and LifeTime. | `list(string)` | ```[ "SizeRestrictions_BODY" ]``` | no |
| domain\_name | Primary host name of the environment (e.g. apps.example.com). Required when certificate\_arn is null. | `string` | `null` | no |
| enable\_waf | Create a WAFv2 web ACL. | `bool` | `true` | no |
| log\_retention\_days | WAF log retention. | `number` | `90` | no |
| rate\_limit\_per\_5min | Requests per 5 minutes per client IP before the rate rule triggers. | `number` | `2000` | no |
| route53\_zone\_id | Public hosted zone used for ACM DNS validation. | `string` | `null` | no |
| subject\_alternative\_names | Extra host names on the created certificate. | `list(string)` | `[]` | no |
| waf\_mode | count (observe only) or block. | `string` | `"count"` | no |

## Outputs

| Name | Description |
|------|-------------|
| certificate\_arn | Validated ACM certificate ARN for the ALB HTTPS listener. |
| web\_acl\_arn | WAFv2 web ACL ARN (null when WAF is disabled). |
<!-- END_TF_DOCS -->
