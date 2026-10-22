data "aws_region" "current" {}
data "aws_elb_service_account" "current" {}

data "aws_ssm_parameter" "windows_ami" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

locals {
  region              = data.aws_region.current.region
  ami_id              = coalesce(var.ami_id, try(nonsensitive(data.aws_ssm_parameter.windows_ami[0].value), null))
  asg_name            = "${var.name}-frontend"
  lifecycle_hook_name = "${var.name}-frontend-launch"
  target_port         = var.target_protocol == "HTTPS" ? 443 : 80
  scaling_enabled     = var.frontend_max_size > var.frontend_min_size

  user_data_common = {
    environment         = var.name
    region              = local.region
    database_address    = var.database_address
    database_port       = var.database_port
    secret_arns_json    = jsonencode(var.secret_arns)
    asg_name            = local.asg_name
    lifecycle_hook_name = local.lifecycle_hook_name
  }

  instance_tags = merge(var.instance_tags, { OutSystemsEnvironment = var.name })
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "OutSystems ALB"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "frontend" {
  name        = "${var.name}-frontend"
  description = "OutSystems front-end servers"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-frontend" }
}

resource "aws_security_group" "controller" {
  name        = "${var.name}-controller"
  description = "OutSystems deployment controller"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-controller" }
}

locals {
  # Port map, see the OutSystems 11 "network requirements" for each role:
  #   12000 Deployment Controller service (controller)
  #   12001 Deployment service (every Platform Server)
  #   5672  RabbitMQ / Cache Invalidation Service (controller)
  sg_ingress = merge(
    { for cidr in var.alb_ingress_cidrs : "alb-443-${cidr}" => { sg = aws_security_group.alb.id, port = 443, cidr = cidr, src = null, desc = "HTTPS from clients" } },
    { for cidr in var.alb_ingress_cidrs : "alb-80-${cidr}" => { sg = aws_security_group.alb.id, port = 80, cidr = cidr, src = null, desc = "HTTP redirect from clients" } },
    {
      fe-app-from-alb          = { sg = aws_security_group.frontend.id, port = local.target_port, cidr = null, src = aws_security_group.alb.id, desc = "App traffic from ALB" }
      fe-12001-from-controller = { sg = aws_security_group.frontend.id, port = 12001, cidr = null, src = aws_security_group.controller.id, desc = "Deployment service from controller" }
      fe-443-from-fe           = { sg = aws_security_group.frontend.id, port = 443, cidr = null, src = aws_security_group.frontend.id, desc = "Platform services between front-ends" }
      ctl-12000-from-fe        = { sg = aws_security_group.controller.id, port = 12000, cidr = null, src = aws_security_group.frontend.id, desc = "Deployment controller from front-ends" }
      ctl-5672-from-fe         = { sg = aws_security_group.controller.id, port = 5672, cidr = null, src = aws_security_group.frontend.id, desc = "Cache invalidation (RabbitMQ) from front-ends" }
      ctl-443-from-fe          = { sg = aws_security_group.controller.id, port = 443, cidr = null, src = aws_security_group.frontend.id, desc = "Platform services from front-ends" }
      ctl-12001-self           = { sg = aws_security_group.controller.id, port = 12001, cidr = null, src = aws_security_group.controller.id, desc = "Deployment service on the controller itself" }
    },
    var.controller_serves_traffic ? {
      ctl-app-from-alb = { sg = aws_security_group.controller.id, port = local.target_port, cidr = null, src = aws_security_group.alb.id, desc = "App traffic from ALB" }
    } : {},
  )
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.sg_ingress

  security_group_id            = each.value.sg
  description                  = each.value.desc
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.src
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "To targets inside the VPC"
  ip_protocol       = "tcp"
  from_port         = local.target_port
  to_port           = local.target_port
  cidr_ipv4         = var.vpc_cidr
}

# Platform servers need outbound HTTPS (OutSystems licensing / Forge, AWS
# APIs via endpoints or NAT) and access to the database and each other.
resource "aws_vpc_security_group_egress_rule" "servers_all" {
  for_each = {
    frontend   = aws_security_group.frontend.id
    controller = aws_security_group.controller.id
  }

  security_group_id = each.value
  description       = "Outbound from platform servers"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Application Load Balancer (+ access logs bucket)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  #checkov:skip=CKV_AWS_21:Access logs are write-once and expire; versioning adds cost without recovery value
  bucket_prefix = "${var.name}-alb-logs-"
  force_destroy = var.force_destroy_log_bucket
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ALB access logging only supports SSE-S3, not SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.alb_log_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "ElbLogDeliveryLegacyRegions"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  statement {
    sid       = "ElbLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.alb_logs.arn,
      "${aws_s3_bucket.alb_logs.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

resource "aws_lb" "this" {
  name               = substr(var.name, 0, 32)
  load_balancer_type = "application"
  internal           = var.alb_internal
  subnets            = var.alb_internal ? var.private_subnet_ids : var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.alb_deletion_protection
  idle_timeout               = var.alb_idle_timeout

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "this" {
  name                 = substr("${var.name}-fe", 0, 32)
  vpc_id               = var.vpc_id
  port                 = local.target_port
  protocol             = var.target_protocol
  target_type          = "instance"
  deregistration_delay = 60

  health_check {
    path                = var.health_check_path
    protocol            = var.target_protocol
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 5
  }

  stickiness {
    type    = "lb_cookie"
    enabled = var.enable_stickiness
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_acl_arn
}

# ---------------------------------------------------------------------------
# Deployment controller (single instance by design)
# ---------------------------------------------------------------------------

resource "aws_instance" "controller" {
  ami                     = local.ami_id
  instance_type           = var.controller_instance_type
  subnet_id               = var.private_subnet_ids[0]
  vpc_security_group_ids  = [aws_security_group.controller.id]
  iam_instance_profile    = var.instance_profile_name
  ebs_optimized           = true
  monitoring              = true
  disable_api_termination = var.termination_protection

  user_data = templatefile("${path.module}/templates/user_data.ps1.tftpl", merge(local.user_data_common, {
    role                  = "controller"
    controller_private_ip = ""
    use_lifecycle_hook    = false
  }))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  tags = merge(local.instance_tags, var.controller_backup_tags, {
    Name           = "${var.name}-controller"
    OutSystemsRole = "controller"
  })

  volume_tags = merge(local.instance_tags, { Name = "${var.name}-controller" })

  lifecycle {
    # Re-baking the AMI or editing bootstrap must not replace a configured controller.
    ignore_changes = [ami, user_data]
  }
}

resource "aws_lb_target_group_attachment" "controller" {
  count = var.controller_serves_traffic ? 1 : 0

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_instance.controller.id
  port             = local.target_port
}

# ---------------------------------------------------------------------------
# Front-ends: launch template + Auto Scaling group
# ---------------------------------------------------------------------------

resource "aws_launch_template" "frontend" {
  name_prefix   = "${var.name}-frontend-"
  image_id      = coalesce(var.frontend_ami_id, local.ami_id)
  instance_type = var.frontend_instance_type
  ebs_optimized = true

  vpc_security_group_ids = [aws_security_group.frontend.id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.ps1.tftpl", merge(local.user_data_common, {
    role                  = "frontend"
    controller_private_ip = aws_instance.controller.private_ip
    use_lifecycle_hook    = var.enable_launch_lifecycle_hook
  })))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size_gb
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.instance_tags, { Name = "${var.name}-frontend", OutSystemsRole = "frontend" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.instance_tags, { Name = "${var.name}-frontend" })
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                = local.asg_name
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = var.frontend_min_size
  max_size            = var.frontend_max_size
  desired_capacity    = var.frontend_desired_capacity
  target_group_arns   = [aws_lb_target_group.this.arn]

  # Windows + Platform Server needs a long time before it is healthy.
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.health_check_grace_period
  protect_from_scale_in     = var.protect_from_scale_in

  launch_template {
    id      = aws_launch_template.frontend.id
    version = aws_launch_template.frontend.latest_version
  }

  dynamic "initial_lifecycle_hook" {
    for_each = var.enable_launch_lifecycle_hook ? [1] : []
    content {
      name                 = local.lifecycle_hook_name
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
      default_result       = "ABANDON"
      heartbeat_timeout    = var.lifecycle_hook_timeout
    }
  }

  dynamic "tag" {
    for_each = merge(local.instance_tags, { Name = "${var.name}-frontend" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    # Scaling policies own the running count after creation.
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu" {
  count = local.scaling_enabled ? 1 : 0

  name                   = "${var.name}-frontend-cpu"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value     = var.cpu_target_percent
    disable_scale_in = !var.allow_scale_in
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}

resource "aws_autoscaling_policy" "requests" {
  count = local.scaling_enabled ? 1 : 0

  name                   = "${var.name}-frontend-requests"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value     = var.requests_per_target
    disable_scale_in = !var.allow_scale_in
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
    }
  }
}
