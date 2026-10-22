# Unit tests for the network module. The AWS provider is mocked, so these runs
# need no credentials and create nothing.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name                  = "os11-test"
  vpc_cidr              = "10.99.0.0/16"
  azs                   = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnet_cidrs   = ["10.99.0.0/24", "10.99.1.0/24"]
  private_subnet_cidrs  = ["10.99.16.0/20", "10.99.32.0/20"]
  database_subnet_cidrs = ["10.99.200.0/24", "10.99.201.0/24"]
  kms_key_arn           = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
}

run "one_subnet_per_tier_per_az" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2
    error_message = "Expected one public, private and database subnet per AZ."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames && aws_vpc.this.enable_dns_support
    error_message = "VPC DNS support and hostnames must be enabled for VPC endpoints."
  }
}

run "nat_per_az_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Without single_nat_gateway there must be one NAT gateway per AZ."
  }
}

run "single_nat_gateway_shares_one" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single_nat_gateway must create exactly one NAT gateway and EIP."
  }
}

run "only_public_and_private_tiers_route_out" {
  command = plan

  # Default routes exist only for the public table (IGW) and each private
  # table (NAT); the database table is declared without any route resource.
  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0" && length(aws_route.private_nat) == 2
    error_message = "Expected one internet route for public and one NAT route per private route table."
  }

  assert {
    condition     = length(aws_route_table_association.database) == 2
    error_message = "Every database subnet must be associated with the isolated database route table."
  }
}

run "flow_logs_capture_all_traffic_encrypted" {
  command = plan

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow logs must capture ALL traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.kms_key_id == var.kms_key_arn
    error_message = "Flow log group must be encrypted with the environment KMS key."
  }
}

run "interface_endpoints_created" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 7
    error_message = "Expected the default seven interface endpoints."
  }
}

run "rejects_single_az" {
  command = plan

  variables {
    azs = ["ap-southeast-1a"]
  }

  expect_failures = [var.azs]
}
