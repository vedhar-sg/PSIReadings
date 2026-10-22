# Test / QA: dedicated controller plus a small front-end farm, close to prod shape.
# No secrets here. Values marked REPLACE must be set before the first plan.
environment         = "test"
region              = "ap-southeast-1"
dr_region           = "ap-southeast-2"
allowed_account_ids = ["111111111111"] # REPLACE with the non-prod account ID

vpc_cidr           = "10.20.0.0/16"
az_count           = 2
single_nat_gateway = true

domain_name     = "test.outsystems.example.com" # REPLACE
route53_zone_id = "Z0000000000000000000"        # REPLACE

alb_internal      = false
alb_ingress_cidrs = ["0.0.0.0/0"]
enable_waf        = true
waf_mode          = "count"

controller_instance_type  = "m6i.xlarge"
frontend_instance_type    = "m6i.large"
controller_serves_traffic = false
frontend_min_size         = 1
frontend_max_size         = 3
frontend_desired_capacity = 1

db_engine                = "sqlserver-se"
db_instance_class        = "db.m6i.large"
db_allocated_storage_gb  = 100
db_multi_az              = false
db_backup_retention_days = 7
db_deletion_protection   = true

termination_protection          = false
log_retention_days              = 60
backup_retention_days           = 14
enable_cross_region_backup_copy = false

alarm_emails = []
