# Network module

Multi-AZ VPC for one OutSystems environment.

- **Public subnets** hold only the ALB and NAT gateways.
- **Private subnets** hold the Platform Server instances, with egress through NAT.
- **Database subnets** are isolated and have no route to the internet.
- **VPC endpoints:** a gateway endpoint for S3, plus interface endpoints for SSM, Secrets Manager, KMS, CloudWatch Logs and metrics. This traffic stays off the NAT gateways.
- **Flow logs** for all traffic go to a KMS-encrypted CloudWatch log group.
- The **default security group** is stripped of all rules.

Part of the [OutSystems 11 on AWS](../../README.md) stack. Tests live in `tests/` and run with `terraform test` (mocked AWS provider, no credentials needed).

## Usage

```hcl
module "network" {
  source = "../modules/network"

  name                  = "os11-dev"
  vpc_cidr              = "10.10.0.0/16"
  azs                   = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnet_cidrs   = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs  = ["10.10.16.0/20", "10.10.32.0/20"]
  database_subnet_cidrs = ["10.10.200.0/24", "10.10.201.0/24"]
  single_nat_gateway    = true
  kms_key_arn           = module.security.kms_key_arn
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
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| azs | Availability zones to spread subnets across (at least two). | `list(string)` | n/a | yes |
| database\_subnet\_cidrs | One isolated subnet CIDR per AZ (RDS). | `list(string)` | n/a | yes |
| kms\_key\_arn | KMS key used to encrypt the flow-log log group. | `string` | n/a | yes |
| name | Name prefix for every network resource (e.g. os11-prod). | `string` | n/a | yes |
| private\_subnet\_cidrs | One private subnet CIDR per AZ (Platform Server instances). | `list(string)` | n/a | yes |
| public\_subnet\_cidrs | One public subnet CIDR per AZ (ALB and NAT gateways only). | `list(string)` | n/a | yes |
| vpc\_cidr | CIDR block of the VPC. | `string` | n/a | yes |
| flow\_log\_retention\_days | Retention for VPC flow logs. | `number` | `90` | no |
| interface\_endpoints | Interface VPC endpoint service suffixes to create. | `list(string)` | ```[ "ssm", "ssmmessages", "ec2messages", "secretsmanager", "kms", "logs", "monitoring" ]``` | no |
| single\_nat\_gateway | Use one shared NAT gateway instead of one per AZ (cheaper, not AZ-resilient). | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| database\_subnet\_ids | Isolated database subnet IDs (RDS). |
| nat\_public\_ips | Elastic IPs of the NAT gateways (outbound address of the platform servers). |
| private\_subnet\_ids | Private subnet IDs (Platform Server instances). |
| public\_subnet\_ids | Public subnet IDs (ALB). |
| vpc\_cidr | VPC CIDR block. |
| vpc\_id | VPC ID. |
<!-- END_TF_DOCS -->
