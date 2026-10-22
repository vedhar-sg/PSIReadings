data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  region = data.aws_region.current.region

  log_groups = {
    windows-system      = "/outsystems/${var.name}/windows/system"
    windows-application = "/outsystems/${var.name}/windows/application"
    iis                 = "/outsystems/${var.name}/iis"
    platform            = "/outsystems/${var.name}/platform-server"
  }

  # CloudWatch agent configuration, distributed through SSM Parameter Store.
  cw_agent_config = {
    agent = { metrics_collection_interval = 60 }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId           = "$${aws:InstanceId}"
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        Memory = {
          measurement = ["% Committed Bytes In Use"]
        }
        LogicalDisk = {
          measurement = ["% Free Space"]
          resources   = ["C:"]
        }
        "Processor" = {
          measurement = ["% Processor Time"]
          resources   = ["_Total"]
        }
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name     = "System"
              event_levels   = ["ERROR", "CRITICAL", "WARNING"]
              log_group_name = local.log_groups.windows-system
            },
            {
              event_name     = "Application"
              event_levels   = ["ERROR", "CRITICAL", "WARNING"]
              log_group_name = local.log_groups.windows-application
            },
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\inetpub\\logs\\LogFiles\\W3SVC*\\*.log"
              log_group_name  = local.log_groups.iis
              log_stream_name = "{instance_id}"
            },
            {
              # Platform Server service logs; application logs live in the
              # OutSystems log database and are read through Service Center.
              file_path       = "C:\\Program Files\\OutSystems\\Platform Server\\logs\\*.log"
              log_group_name  = local.log_groups.platform
              log_stream_name = "{instance_id}"
            },
          ]
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Log groups + CloudWatch agent rollout via SSM
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ssm_parameter" "cw_agent_config" {
  #checkov:skip=CKV2_AWS_34:CloudWatch agent configuration contains no sensitive data
  name  = "AmazonCloudWatch-${var.name}"
  type  = "String"
  tier  = "Advanced"
  value = jsonencode(local.cw_agent_config)
}

resource "aws_ssm_association" "install_cw_agent" {
  name             = "AWS-ConfigureAWSPackage"
  association_name = "${var.name}-install-cloudwatch-agent"

  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }

  targets {
    key    = "tag:OutSystemsEnvironment"
    values = [var.name]
  }
}

resource "aws_ssm_association" "configure_cw_agent" {
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "${var.name}-configure-cloudwatch-agent"

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cw_agent_config.name
    optionalRestart               = "yes"
  }

  targets {
    key    = "tag:OutSystemsEnvironment"
    values = [var.name]
  }

  depends_on = [aws_ssm_association.install_cw_agent]
}

# Daily patch compliance scan only. Installing patches restarts IIS / Platform
# Server, so installs are run deliberately per the patching runbook.
resource "aws_ssm_association" "patch_scan" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "${var.name}-patch-scan"
  schedule_expression = var.patch_scan_schedule

  parameters = {
    Operation = "Scan"
  }

  targets {
    key    = "tag:OutSystemsEnvironment"
    values = [var.name]
  }
}

# ---------------------------------------------------------------------------
# Alarm notifications
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = var.kms_key_arn
}

# Email subscriptions stay pending until each recipient confirms.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]
  alb_dims      = { LoadBalancer = var.alb_arn_suffix }
  tg_dims       = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }

  alarms = {
    alb-5xx = {
      namespace = "AWS/ApplicationELB", metric = "HTTPCode_ELB_5XX_Count", stat = "Sum", dims = local.alb_dims
      threshold = var.alb_5xx_threshold, op = "GreaterThanThreshold", periods = 3
      desc      = "ALB returned 5xx (no healthy targets or ALB errors)"
    }
    target-5xx = {
      namespace = "AWS/ApplicationELB", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", dims = local.tg_dims
      threshold = var.target_5xx_threshold, op = "GreaterThanThreshold", periods = 3
      desc      = "OutSystems applications returned 5xx"
    }
    unhealthy-hosts = {
      namespace = "AWS/ApplicationELB", metric = "UnHealthyHostCount", stat = "Maximum", dims = local.tg_dims
      threshold = 0, op = "GreaterThanThreshold", periods = 3
      desc      = "At least one platform server failed its ALB health check"
    }
    response-time = {
      namespace = "AWS/ApplicationELB", metric = "TargetResponseTime", stat = "Average", dims = local.tg_dims
      threshold = var.response_time_threshold_seconds, op = "GreaterThanThreshold", periods = 5
      desc      = "Average response time is high"
    }
    frontend-cpu = {
      namespace = "AWS/EC2", metric = "CPUUtilization", stat = "Average", dims = { AutoScalingGroupName = var.frontend_asg_name }
      threshold = var.cpu_threshold_percent, op = "GreaterThanThreshold", periods = 5
      desc      = "Front-end CPU is high"
    }
    controller-cpu = {
      namespace = "AWS/EC2", metric = "CPUUtilization", stat = "Average", dims = { InstanceId = var.controller_instance_id }
      threshold = var.cpu_threshold_percent, op = "GreaterThanThreshold", periods = 5
      desc      = "Controller CPU is high (long or frequent publishes)"
    }
    controller-disk = {
      namespace = "CWAgent", metric = "LogicalDisk % Free Space", stat = "Minimum"
      dims      = { InstanceId = var.controller_instance_id, instance = "C:", objectname = "LogicalDisk" }
      threshold = var.disk_free_threshold_percent, op = "LessThanThreshold", periods = 2
      desc      = "Controller C: drive is running out of space"
    }
    controller-status-instance = {
      namespace = "AWS/EC2", metric = "StatusCheckFailed_Instance", stat = "Maximum", dims = { InstanceId = var.controller_instance_id }
      threshold = 0, op = "GreaterThanThreshold", periods = 3
      desc      = "Controller OS-level status check failed"
    }
    db-cpu = {
      namespace = "AWS/RDS", metric = "CPUUtilization", stat = "Average", dims = { DBInstanceIdentifier = var.db_instance_identifier }
      threshold = var.cpu_threshold_percent, op = "GreaterThanThreshold", periods = 5
      desc      = "Database CPU is high"
    }
    db-storage = {
      namespace = "AWS/RDS", metric = "FreeStorageSpace", stat = "Minimum", dims = { DBInstanceIdentifier = var.db_instance_identifier }
      threshold = var.db_free_storage_threshold_gb * 1024 * 1024 * 1024, op = "LessThanThreshold", periods = 2
      desc      = "Database free storage is low"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.desc
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.stat
  dimensions          = each.value.dims
  period              = 60
  evaluation_periods  = each.value.periods
  threshold           = each.value.threshold
  comparison_operator = each.value.op
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Hardware failure on the single controller: let EC2 move it to healthy
# hardware automatically (same instance ID, IP and EBS volumes).
resource "aws_cloudwatch_metric_alarm" "controller_recover" {
  alarm_name          = "${var.name}-controller-auto-recover"
  alarm_description   = "Recover the controller onto new hardware after a system status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  dimensions          = { InstanceId = var.controller_instance_id }
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = concat(["arn:${data.aws_partition.current.partition}:automate:${local.region}:ec2:recover"], local.alarm_actions)
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Requests and errors", region = local.region, stat = "Sum", period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Response time and healthy hosts", region = local.region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p95" }],
            [".", "HealthyHostCount", ".", ".", ".", ".", { stat = "Minimum", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "Platform server CPU", region = local.region, stat = "Average", period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.frontend_asg_name, { label = "front-ends" }],
            [".", ".", "InstanceId", var.controller_instance_id, { label = "controller" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Database", region = local.region, period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier, { stat = "Average" }],
            [".", "DatabaseConnections", ".", ".", { stat = "Maximum", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
