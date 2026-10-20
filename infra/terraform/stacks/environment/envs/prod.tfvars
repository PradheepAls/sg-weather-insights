environment             = "prod"
network                 = "prod"
is_production           = true
public_hostname         = "weather.example.gov.sg"
public_zone_id          = "Z0000000000000000000"
certificate_arn         = "arn:aws:acm:ap-southeast-1:111122223333:certificate/replace-me"
alb_internal            = false
alb_ingress_cidrs       = ["0.0.0.0/0"]
admin_cidrs             = ["10.20.0.0/16", "10.99.0.0/16"]
platform_server_version = "11.31.0"
license_s3_key          = "licenses/prod.lic"

dedicated_controller     = true
controller_instance_type = "m6i.xlarge"
frontend_instance_type   = "m6i.xlarge"
frontend_min             = 2
frontend_max             = 6
frontend_desired         = 2

db_instance_class        = "db.m6i.xlarge"
db_multi_az              = true
db_backup_retention_days = 35
deletion_protection      = true
enable_waf               = true
patch_operation          = "Scan"
