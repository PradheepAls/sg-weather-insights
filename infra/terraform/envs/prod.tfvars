environment             = "prod"
is_production           = true
vpc_cidr                = "10.30.0.0/16"
alb_internal            = false
alb_ingress_cidrs       = ["0.0.0.0/0"]
admin_cidrs             = ["10.99.0.0/16"]
certificate_arn         = "arn:aws:acm:ap-southeast-1:111122223333:certificate/replace-me"
platform_server_version = "11.31.0"
license_bucket          = "replace-me-licences"
license_key             = "licenses/prod.lic"

frontend_count           = 2
db_instance_class        = "db.m6i.xlarge"
db_multi_az              = true
db_backup_retention_days = 35
deletion_protection      = true
alarm_email              = "oncall@example.gov.sg"
