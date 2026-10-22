data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count zones are used, so new AZs never change the layout
  state = "available"
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 VPC: public /24s at .0-.2, private /20s from .16, database /24s at .200+.
  public_subnet_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 1)]
  database_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 200 + i)]

  backup_tag = { BackupPlan = local.name }
}

module "security" {
  source = "../modules/security"

  name                        = local.name
  secret_recovery_window_days = var.secret_recovery_window_days
  installer_bucket_arn        = var.installer_bucket_arn
  extra_readable_secret_arns  = var.extra_readable_secret_arns
}

module "network" {
  source = "../modules/network"

  name                    = local.name
  vpc_cidr                = var.vpc_cidr
  azs                     = local.azs
  public_subnet_cidrs     = local.public_subnet_cidrs
  private_subnet_cidrs    = local.private_subnet_cidrs
  database_subnet_cidrs   = local.database_subnet_cidrs
  single_nat_gateway      = var.single_nat_gateway
  kms_key_arn             = module.security.kms_key_arn
  flow_log_retention_days = var.log_retention_days
}

module "edge" {
  source = "../modules/edge"

  name               = local.name
  certificate_arn    = var.certificate_arn
  domain_name        = var.domain_name
  route53_zone_id    = var.route53_zone_id
  enable_waf         = var.enable_waf
  waf_mode           = var.waf_mode
  kms_key_arn        = module.security.kms_key_arn
  log_retention_days = var.log_retention_days
}

module "database" {
  source = "../modules/database"

  name       = local.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.database_subnet_ids
  allowed_security_group_ids = {
    controller = module.platform.security_group_ids.controller
    frontend   = module.platform.security_group_ids.frontend
  }

  engine                   = var.db_engine
  engine_version           = var.db_engine_version
  license_model            = var.db_license_model
  instance_class           = var.db_instance_class
  allocated_storage_gb     = var.db_allocated_storage_gb
  max_allocated_storage_gb = var.db_max_allocated_storage_gb
  multi_az                 = var.db_multi_az
  backup_retention_days    = var.db_backup_retention_days
  deletion_protection      = var.db_deletion_protection
  skip_final_snapshot      = !var.db_deletion_protection
  kms_key_arn              = module.security.kms_key_arn
  tags                     = local.backup_tag
}

module "platform" {
  source = "../modules/platform"

  name               = local.name
  vpc_id             = module.network.vpc_id
  vpc_cidr           = module.network.vpc_cidr
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  alb_internal            = var.alb_internal
  alb_ingress_cidrs       = var.alb_ingress_cidrs
  alb_deletion_protection = var.termination_protection
  certificate_arn         = module.edge.certificate_arn
  enable_waf              = var.enable_waf
  waf_acl_arn             = module.edge.web_acl_arn
  target_protocol         = var.target_protocol
  health_check_path       = var.health_check_path
  enable_stickiness       = var.enable_stickiness

  ami_id                    = var.ami_id
  frontend_ami_id           = var.frontend_ami_id
  controller_instance_type  = var.controller_instance_type
  frontend_instance_type    = var.frontend_instance_type
  root_volume_size_gb       = var.root_volume_size_gb
  instance_profile_name     = module.security.instance_profile_name
  kms_key_arn               = module.security.kms_key_arn
  termination_protection    = var.termination_protection
  controller_serves_traffic = var.controller_serves_traffic
  controller_backup_tags    = local.backup_tag
  force_destroy_log_bucket  = !var.termination_protection

  database_address = module.database.address
  database_port    = module.database.port
  secret_arns = merge(module.security.secret_arns, {
    db_master = module.database.master_user_secret_arn
  })

  frontend_min_size            = var.frontend_min_size
  frontend_max_size            = var.frontend_max_size
  frontend_desired_capacity    = var.frontend_desired_capacity
  allow_scale_in               = var.allow_scale_in
  enable_launch_lifecycle_hook = var.enable_launch_lifecycle_hook
}

# The RDS-managed master secret is created with the database, so grant read
# access to it separately (avoids a module dependency cycle).
data "aws_iam_policy_document" "read_db_master_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.database.master_user_secret_arn]
  }
}

resource "aws_iam_role_policy" "read_db_master_secret" {
  name   = "read-db-master-secret"
  role   = module.security.instance_role_name
  policy = data.aws_iam_policy_document.read_db_master_secret.json
}

module "observability" {
  source = "../modules/observability"

  name                    = local.name
  kms_key_arn             = module.security.kms_key_arn
  log_retention_days      = var.log_retention_days
  alarm_emails            = var.alarm_emails
  alb_arn_suffix          = module.platform.alb_arn_suffix
  target_group_arn_suffix = module.platform.target_group_arn_suffix
  frontend_asg_name       = module.platform.frontend_asg_name
  controller_instance_id  = module.platform.controller_instance_id
  db_instance_identifier  = module.database.identifier
}

module "backup" {
  source = "../modules/dr-backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                     = local.name
  kms_key_arn              = module.security.kms_key_arn
  retention_days           = var.backup_retention_days
  enable_cross_region_copy = var.enable_cross_region_backup_copy
  dr_retention_days        = var.dr_backup_retention_days
  selection_tag_key        = keys(local.backup_tag)[0]
  selection_tag_value      = values(local.backup_tag)[0]
  force_destroy            = !var.termination_protection
}
