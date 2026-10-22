# Production: three AZs, NAT per AZ, Multi-AZ database, WAF blocking,
# deletion protection everywhere and cross-region backup copies.
# No secrets here. Values marked REPLACE must be set before the first plan.
environment         = "prod"
region              = "ap-southeast-1"
dr_region           = "ap-southeast-2"
allowed_account_ids = ["222222222222"] # REPLACE with the prod account ID

vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false

domain_name     = "apps.example.com"     # REPLACE
route53_zone_id = "Z0000000000000000000" # REPLACE

alb_internal      = false
alb_ingress_cidrs = ["0.0.0.0/0"]
enable_waf        = true
waf_mode          = "block"

controller_instance_type  = "m6i.xlarge"
frontend_instance_type    = "m6i.xlarge"
controller_serves_traffic = false
frontend_min_size         = 2
frontend_max_size         = 6
frontend_desired_capacity = 2
allow_scale_in            = false

db_engine                   = "sqlserver-se"
db_instance_class           = "db.m6i.xlarge"
db_allocated_storage_gb     = 200
db_max_allocated_storage_gb = 1000
db_multi_az                 = true
db_backup_retention_days    = 35
db_deletion_protection      = true

termination_protection          = true
log_retention_days              = 365
backup_retention_days           = 35
enable_cross_region_backup_copy = true
dr_backup_retention_days        = 35

alarm_emails = []
