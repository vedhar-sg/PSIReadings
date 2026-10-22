# Unit tests for the database module (mocked AWS provider, plan only).

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name           = "os11-test"
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids     = ["subnet-0a", "subnet-0b"]
  instance_class = "db.m6i.large"
  kms_key_arn    = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
  allowed_security_group_ids = {
    controller = "sg-0controller"
    frontend   = "sg-0frontend"
  }
}

run "sql_server_defaults_are_secure" {
  command = plan

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "The master password must be managed by RDS in Secrets Manager, never set in code."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && aws_db_instance.this.kms_key_id == var.kms_key_arn
    error_message = "Storage must be encrypted with the environment KMS key."
  }

  assert {
    condition     = !aws_db_instance.this.publicly_accessible
    error_message = "The database must never be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.this.port == 1433 && aws_db_instance.this.engine == "sqlserver-se"
    error_message = "SQL Server must listen on 1433."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && aws_db_instance.this.final_snapshot_identifier == "os11-test-final"
    error_message = "Deletion protection and a final snapshot are the defaults."
  }
}

run "only_platform_security_groups_reach_the_db" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.db) == 2
    error_message = "Expected one ingress rule per allowed security group."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.db : r.cidr_ipv4 == null && r.from_port == 1433])
    error_message = "DB ingress must reference security groups on the DB port, never CIDRs."
  }
}

run "oracle_uses_oracle_port_and_logs" {
  command = plan

  variables {
    engine         = "oracle-se2"
    engine_version = "19"
  }

  assert {
    condition     = aws_db_instance.this.port == 1521
    error_message = "Oracle must listen on 1521."
  }

  assert {
    condition     = contains(aws_db_instance.this.enabled_cloudwatch_logs_exports, "alert")
    error_message = "Oracle must export alert logs."
  }
}

run "monitoring_can_be_disabled" {
  command = plan

  variables {
    monitoring_interval = 0
  }

  assert {
    condition     = length(aws_iam_role.monitoring) == 0
    error_message = "No enhanced monitoring role when monitoring_interval is 0."
  }
}

run "throwaway_env_skips_final_snapshot" {
  command = plan

  variables {
    deletion_protection = false
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == null
    error_message = "No final snapshot identifier when skip_final_snapshot is set."
  }
}

run "rejects_unsupported_engine" {
  command = plan

  variables {
    engine = "postgres"
  }

  expect_failures = [var.engine]
}
