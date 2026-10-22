# Integration test for the whole stack with mocked AWS providers.
#
# Run once per environment with that environment's real tfvars, e.g.
#   terraform -chdir=stack test -var-file=../envs/prod/terraform.tfvars
# (scripts/test.sh does this for every environment).
#
# It proves the modules wire together and plan for that environment's settings
# (including the guardrail preconditions in stack/guardrails.tf), then proves
# the guardrails reject unsafe settings.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::114774131450:root" }
  }

  override_resource {
    target          = module.edge.aws_acm_certificate.this[0]
    override_during = plan
    values = {
      arn = "arn:aws:acm:ap-southeast-1:111111111111:certificate/test"
      domain_validation_options = [{
        domain_name           = "apps.example.com"
        resource_record_name  = "_x.apps.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_y.acm-validations.aws."
      }]
    }
  }
}

mock_provider "aws" {
  alias = "dr"
}

run "stack_plans_with_environment_settings" {
  command = plan

  assert {
    condition     = length(var.allowed_account_ids) > 0
    error_message = "allowed_account_ids must pin the target account."
  }

  assert {
    condition     = terraform_data.guardrails.input == var.environment
    error_message = "Guardrails must be evaluated for this environment."
  }
}

# The negative cases below override the loaded tfvars to prove that the
# guardrails in stack/guardrails.tf actually stop an unsafe plan.

run "prod_without_multi_az_is_rejected" {
  command = plan

  variables {
    environment               = "prod"
    db_multi_az               = false
    db_deletion_protection    = true
    termination_protection    = true
    az_count                  = 3
    single_nat_gateway        = false
    frontend_min_size         = 2
    frontend_desired_capacity = 2
    frontend_max_size         = 4
    enable_waf                = true
    waf_mode                  = "block"
  }

  expect_failures = [terraform_data.guardrails]
}

run "prod_with_waf_in_count_mode_is_rejected" {
  command = plan

  variables {
    environment = "prod"
    waf_mode    = "count"
  }

  expect_failures = [terraform_data.guardrails]
}

run "unprotected_lifetime_is_rejected" {
  command = plan

  variables {
    environment            = "lifetime"
    termination_protection = false
  }

  expect_failures = [terraform_data.guardrails]
}

run "alb_without_targets_is_rejected" {
  command = plan

  variables {
    environment               = "dev"
    controller_serves_traffic = false
    frontend_min_size         = 0
    frontend_desired_capacity = 0
    frontend_max_size         = 0
  }

  expect_failures = [terraform_data.guardrails]
}
