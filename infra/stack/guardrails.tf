# Environment guardrails. These preconditions fail `terraform plan` (locally,
# in CI and in tests) when an environment's settings drift below the agreed
# baseline, before anything is sent to AWS.

resource "terraform_data" "guardrails" {
  input = var.environment

  lifecycle {
    precondition {
      condition     = var.frontend_min_size <= var.frontend_desired_capacity && var.frontend_desired_capacity <= var.frontend_max_size
      error_message = "Front-end sizes must satisfy min <= desired <= max."
    }

    precondition {
      condition     = var.frontend_max_size > 0 || var.controller_serves_traffic
      error_message = "With no front-ends the controller must serve traffic, or the ALB has no targets."
    }

    precondition {
      condition = var.environment != "prod" || (
        var.db_multi_az && var.db_deletion_protection && var.termination_protection &&
        var.az_count >= 3 && !var.single_nat_gateway && var.frontend_min_size >= 2
      )
      error_message = "prod requires Multi-AZ RDS, deletion/termination protection, 3 AZs, a NAT gateway per AZ and at least two front-ends."
    }

    precondition {
      condition     = var.environment != "prod" || (var.enable_waf && var.waf_mode == "block")
      error_message = "prod requires WAF in block mode."
    }

    precondition {
      condition = var.environment != "prod" || (
        var.enable_cross_region_backup_copy && var.db_backup_retention_days >= 30 && var.log_retention_days >= 365
      )
      error_message = "prod requires cross-region backup copies, >= 30 days of point-in-time recovery and 365 days of logs."
    }

    precondition {
      condition     = var.environment != "lifetime" || (var.db_deletion_protection && var.termination_protection && var.enable_cross_region_backup_copy)
      error_message = "LifeTime manages every environment; it must be deletion-protected and copied cross-region."
    }
  }
}
