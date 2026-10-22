# Unit tests for the edge module (mocked AWS provider, plan only).

mock_provider "aws" {
  # The real provider knows domain_validation_options at plan time; the mock
  # must too, or the validation-record for_each cannot be planned.
  override_resource {
    target          = aws_acm_certificate.this[0]
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

variables {
  name            = "os11-test"
  domain_name     = "apps.example.com"
  route53_zone_id = "Z0000000000000000000"
  kms_key_arn     = "arn:aws:kms:ap-southeast-1:111111111111:key/test"
}

run "issues_dns_validated_certificate" {
  command = plan

  assert {
    condition     = length(aws_acm_certificate.this) == 1 && aws_acm_certificate.this[0].validation_method == "DNS"
    error_message = "A DNS-validated certificate must be created when no certificate_arn is given."
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1
    error_message = "One validation record per domain is expected."
  }
}

run "reuses_existing_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:ap-southeast-1:111111111111:certificate/existing"
    domain_name     = null
    route53_zone_id = null
  }

  assert {
    condition     = length(aws_acm_certificate.this) == 0
    error_message = "No certificate should be created when certificate_arn is supplied."
  }

  assert {
    condition     = output.certificate_arn == var.certificate_arn
    error_message = "The supplied certificate ARN must be passed through."
  }
}

run "requires_certificate_or_domain" {
  command = plan

  variables {
    route53_zone_id = null
  }

  expect_failures = [var.domain_name]
}

run "waf_count_mode_by_default" {
  command = plan

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this[0].rule :
      length(r.override_action) == 0 || length(r.override_action[0].count) == 1
    ])
    error_message = "In count mode every managed rule group must override to count."
  }
}

run "waf_block_mode" {
  command = plan

  variables {
    waf_mode = "block"
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this[0].rule :
      length(r.override_action) == 0 || length(r.override_action[0].none) == 1
    ])
    error_message = "In block mode managed rule groups must use their own actions."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this[0].rule : r.name == "rate-limit-per-ip" && length(r.action[0].block) == 1
    ])
    error_message = "The rate limit rule must block in block mode."
  }
}

run "service_center_uploads_not_blocked" {
  command = plan

  assert {
    condition = anytrue(flatten([
      for r in aws_wafv2_web_acl.this[0].rule : [
        for o in r.statement[0].managed_rule_group_statement[0].rule_action_override : o.name == "SizeRestrictions_BODY"
      ] if r.name == "AWSManagedRulesCommonRuleSet"
    ]))
    error_message = "SizeRestrictions_BODY must be downgraded to count so OutSystems uploads are not blocked."
  }
}

run "waf_logs_use_required_prefix" {
  command = plan

  assert {
    condition     = startswith(aws_cloudwatch_log_group.waf[0].name, "aws-waf-logs-")
    error_message = "WAF log groups must start with aws-waf-logs-."
  }
}

run "waf_can_be_disabled" {
  command = plan

  variables {
    enable_waf = false
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0 && output.web_acl_arn == null
    error_message = "No web ACL when enable_waf is false."
  }
}

run "rejects_unknown_waf_mode" {
  command = plan

  variables {
    waf_mode = "monitor"
  }

  expect_failures = [var.waf_mode]
}
