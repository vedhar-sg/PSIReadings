# LifeTime: dedicated single-server environment that manages Dev/Test/Prod.
# Keep it internal if your team reaches it over VPN / Direct Connect.
# No secrets here. Values marked REPLACE must be set before the first plan.
environment         = "lifetime"
region              = "ap-southeast-1"
dr_region           = "ap-southeast-2"
allowed_account_ids = ["111111111111"] # REPLACE with the account hosting LifeTime

vpc_cidr           = "10.40.0.0/16"
az_count           = 2
single_nat_gateway = true

domain_name     = "lifetime.outsystems.example.com" # REPLACE
route53_zone_id = "Z0000000000000000000"            # REPLACE

alb_internal      = false
alb_ingress_cidrs = ["0.0.0.0/0"] # Strongly consider office/VPN ranges only
enable_waf        = true
waf_mode          = "block"

controller_instance_type  = "m6i.xlarge"
frontend_instance_type    = "m6i.large"
controller_serves_traffic = true
frontend_min_size         = 0
frontend_max_size         = 0
frontend_desired_capacity = 0

db_engine                = "sqlserver-se"
db_instance_class        = "db.m6i.large"
db_allocated_storage_gb  = 100
db_multi_az              = false
db_backup_retention_days = 14
db_deletion_protection   = true

termination_protection          = true
log_retention_days              = 90
backup_retention_days           = 35
enable_cross_region_backup_copy = true

alarm_emails = []
