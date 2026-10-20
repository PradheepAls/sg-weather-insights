data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "foundation.tfstate"
    region = var.region
  }
}

locals {
  f   = data.terraform_remote_state.foundation.outputs
  net = local.f.networks[var.network]
}

module "environment" {
  source = "../../modules/outsystems-environment"

  project       = var.project
  environment   = var.environment
  is_production = var.is_production

  vpc_id            = local.net.vpc_id
  public_subnet_ids = local.net.public_subnet_ids
  app_subnet_ids    = local.net.app_subnet_ids
  data_subnet_ids   = local.net.data_subnet_ids
  lifetime_cidr     = local.f.networks.nonprod.cidr

  alb_internal      = var.alb_internal
  alb_ingress_cidrs = var.alb_ingress_cidrs
  admin_cidrs       = var.admin_cidrs
  certificate_arn   = var.certificate_arn
  public_hostname   = var.public_hostname
  public_zone_id    = var.public_zone_id
  private_zone_id   = local.f.private_zone_id
  private_zone_name = local.f.private_zone_name

  kms_key_arn      = local.f.kms_key_arn
  artifacts_bucket = local.f.artifacts_bucket
  alb_logs_bucket  = local.f.alb_logs_bucket
  alarm_topic_arn  = local.f.alarm_topic_arn

  platform_server_version  = var.platform_server_version
  license_s3_key           = var.license_s3_key
  dedicated_controller     = var.dedicated_controller
  controller_instance_type = var.controller_instance_type
  frontend_instance_type   = var.frontend_instance_type
  frontend_min             = var.frontend_min
  frontend_max             = var.frontend_max
  frontend_desired         = var.frontend_desired

  db_instance_class        = var.db_instance_class
  db_multi_az              = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  deletion_protection      = var.deletion_protection

  enable_waf      = var.enable_waf
  patch_operation = var.patch_operation
}
