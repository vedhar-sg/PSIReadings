# Dev: one combined controller/front-end server, cheapest resilient layout.
# No secrets here. Values marked REPLACE must be set before the first plan.
environment         = "dev"
region              = "ap-southeast-1"
dr_region           = "ap-southeast-2"
allowed_account_ids = ["111111111111"] # REPLACE with the dev/non-prod account ID

vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

# TLS: either an existing ACM certificate ARN, or a domain + Route 53 zone.
domain_name     = "dev.outsystems.example.com" # REPLACE
route53_zone_id = "Z0000000000000000000"       # REPLACE
# certificate_arn = "arn:aws:acm:ap-southeast-1:111111111111:certificate/..."

alb_internal      = false
alb_ingress_cidrs = ["0.0.0.0/0"] # Consider restricting to office/VPN ranges
enable_waf        = true
waf_mode          = "count"

controller_instance_type  = "m6i.xlarge"
frontend_instance_type    = "m6i.large"
controller_serves_traffic = true
frontend_min_size         = 0
frontend_max_size         = 2
frontend_desired_capacity = 0

db_engine                = "sqlserver-se"
db_instance_class        = "db.m6i.large"
db_allocated_storage_gb  = 100
db_multi_az              = false
db_backup_retention_days = 7
db_deletion_protection   = false

termination_protection          = false
secret_recovery_window_days     = 7
log_retention_days              = 30
backup_retention_days           = 7
enable_cross_region_backup_copy = false

alarm_emails = [] # e.g. ["platform-team@example.com"]
