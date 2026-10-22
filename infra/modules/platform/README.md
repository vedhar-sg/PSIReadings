# Platform module

OutSystems 11 Platform Server compute and load balancing.

- **ALB:**
  - TLS 1.2/1.3, HTTP to HTTPS redirect, invalid headers dropped;
  - access logs in S3;
  - optional WAF association.
- **Controller:** a single Windows Server 2022 instance running the Deployment Controller and RabbitMQ cache invalidation. It requires IMDSv2 and has encrypted EBS. It can also serve app traffic in single-server environments.
- **Front-ends:** a launch template plus Auto Scaling group across private subnets.
  - Target-tracking scale-out on CPU and requests per target.
  - Scale-in is off unless `allow_scale_in`.
  - Optional launch lifecycle hook, for golden-AMI bootstrap.
- **Security groups** follow the OutSystems network requirements: 443 from the ALB, 12000/12001 between controller and front-ends, and 5672 for RabbitMQ.
- **User data** installs the IIS/.NET features and writes `C:\ProgramData\OutSystemsBootstrap\environment.json`, which holds secret **ARNs** only. It runs `setup.ps1` if a golden AMI provides one.

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "platform" {
  source = "../modules/platform"

  name                      = "os11-dev"
  vpc_id                    = module.network.vpc_id
  vpc_cidr                  = module.network.vpc_cidr
  public_subnet_ids         = module.network.public_subnet_ids
  private_subnet_ids        = module.network.private_subnet_ids
  certificate_arn           = module.edge.certificate_arn
  waf_acl_arn               = module.edge.web_acl_arn
  controller_instance_type  = "m6i.xlarge"
  frontend_instance_type    = "m6i.large"
  instance_profile_name     = module.security.instance_profile_name
  kms_key_arn               = module.security.kms_key_arn
  database_address          = module.database.address
  database_port             = module.database.port
  frontend_min_size         = 1
  frontend_max_size         = 3
  frontend_desired_capacity = 1
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
| [aws_autoscaling_group.frontend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_policy.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_autoscaling_policy.requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_instance.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_launch_template.frontend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_s3_bucket.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.frontend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.servers_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_elb_service_account.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_iam_policy_document.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.windows_ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| certificate\_arn | ACM certificate for the HTTPS listener. | `string` | n/a | yes |
| controller\_instance\_type | Controller instance type. | `string` | n/a | yes |
| database\_address | Database host, written to the bootstrap environment file. | `string` | n/a | yes |
| database\_port | Database port. | `number` | n/a | yes |
| frontend\_desired\_capacity | Initial front-end count (later managed by scaling policies). | `number` | n/a | yes |
| frontend\_instance\_type | Front-end instance type. | `string` | n/a | yes |
| frontend\_max\_size | Maximum front-ends. | `number` | n/a | yes |
| frontend\_min\_size | Minimum front-ends. | `number` | n/a | yes |
| instance\_profile\_name | IAM instance profile for all platform servers. | `string` | n/a | yes |
| kms\_key\_arn | KMS key for EBS volumes. | `string` | n/a | yes |
| name | Name prefix (e.g. os11-prod). | `string` | n/a | yes |
| private\_subnet\_ids | Private subnets for instances (and an internal ALB). | `list(string)` | n/a | yes |
| public\_subnet\_ids | Public subnets for an internet-facing ALB. | `list(string)` | n/a | yes |
| vpc\_cidr | VPC CIDR (ALB egress scope). | `string` | n/a | yes |
| vpc\_id | VPC ID. | `string` | n/a | yes |
| alb\_deletion\_protection | Protect the ALB from deletion. | `bool` | `false` | no |
| alb\_idle\_timeout | ALB idle timeout in seconds (long-running Service Center publishes benefit from a higher value). | `number` | `300` | no |
| alb\_ingress\_cidrs | Client CIDRs allowed to reach the ALB. | `list(string)` | ```[ "0.0.0.0/0" ]``` | no |
| alb\_internal | Make the ALB internal (reachable only from the VPC / connected networks). | `bool` | `false` | no |
| alb\_log\_retention\_days | Days to keep ALB access logs. | `number` | `90` | no |
| allow\_scale\_in | Let scaling policies remove front-ends. Keep false until removal is automated (a front-end must also be disabled in Service Center). | `bool` | `false` | no |
| ami\_id | AMI for the controller (and front-ends unless frontend\_ami\_id is set). Null uses the latest Windows Server 2022 base AMI. | `string` | `null` | no |
| controller\_backup\_tags | Tags that select the controller for AWS Backup. | `map(string)` | `{}` | no |
| controller\_serves\_traffic | Register the controller in the ALB target group (single-server environments such as LifeTime or a small Dev). | `bool` | `false` | no |
| cpu\_target\_percent | Target average CPU for the front-end group. | `number` | `60` | no |
| enable\_launch\_lifecycle\_hook | Hold new front-ends in Pending:Wait until the bootstrap script signals CONTINUE (requires setup.ps1 in a golden AMI). | `bool` | `false` | no |
| enable\_stickiness | Enable ALB cookie stickiness (useful for Traditional Web apps). | `bool` | `false` | no |
| enable\_waf | Associate waf\_acl\_arn with the ALB. | `bool` | `true` | no |
| force\_destroy\_log\_bucket | Allow destroying the ALB log bucket while it still holds logs. | `bool` | `false` | no |
| frontend\_ami\_id | Golden AMI for front-ends with Platform Server pre-installed. Null falls back to ami\_id. | `string` | `null` | no |
| health\_check\_grace\_period | Seconds before a new front-end is health-checked. | `number` | `1800` | no |
| health\_check\_matcher | HTTP codes treated as healthy. | `string` | `"200-399"` | no |
| health\_check\_path | Target health check path. Point it at a lightweight page of a deployed module once one exists. | `string` | `"/"` | no |
| instance\_tags | Extra tags for instances and volumes. | `map(string)` | `{}` | no |
| lifecycle\_hook\_timeout | Seconds the launch lifecycle hook waits before abandoning the instance. | `number` | `3600` | no |
| protect\_from\_scale\_in | Set scale-in protection on new front-end instances. | `bool` | `false` | no |
| requests\_per\_target | Target ALB requests per front-end per minute. | `number` | `1000` | no |
| root\_volume\_size\_gb | Root (C:) volume size. | `number` | `150` | no |
| secret\_arns | Secret ARNs (not values) written to the bootstrap environment file. | `map(string)` | `{}` | no |
| ssl\_policy | ALB TLS policy. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| target\_protocol | Protocol from the ALB to IIS (HTTPS needs a certificate bound in IIS; self-signed is fine). | `string` | `"HTTPS"` | no |
| termination\_protection | Enable EC2 termination protection on the controller. | `bool` | `false` | no |
| waf\_acl\_arn | WAFv2 web ACL ARN. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| alb\_arn\_suffix | ALB ARN suffix (CloudWatch dimension). |
| alb\_dns\_name | ALB DNS name (point your environment host name at it). |
| alb\_zone\_id | ALB hosted zone ID for Route 53 alias records. |
| controller\_instance\_id | Controller EC2 instance ID (connect with SSM Session Manager / Fleet Manager). |
| controller\_private\_ip | Controller private IP (needed by front-ends in the Configuration Tool). |
| frontend\_asg\_name | Front-end Auto Scaling group name. |
| security\_group\_ids | Security groups by role. |
| target\_group\_arn\_suffix | Target group ARN suffix (CloudWatch dimension). |
<!-- END_TF_DOCS -->
