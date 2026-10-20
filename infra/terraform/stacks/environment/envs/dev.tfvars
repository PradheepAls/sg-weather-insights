environment             = "dev"
network                 = "nonprod"
public_hostname         = "weather-dev.example.gov.sg"
certificate_arn         = "arn:aws:acm:ap-southeast-1:111122223333:certificate/replace-me"
alb_internal            = true
alb_ingress_cidrs       = ["10.20.0.0/16", "10.99.0.0/16"]
admin_cidrs             = ["10.20.0.0/16", "10.99.0.0/16"]
platform_server_version = "11.31.0"
license_s3_key          = "licenses/dev.lic"
# Controller doubles as the only front-end; scale out by raising frontend_* if needed.
frontend_max      = 2
frontend_desired  = 0
db_instance_class = "db.m6i.large"
