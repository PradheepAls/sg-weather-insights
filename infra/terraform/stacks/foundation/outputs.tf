output "kms_key_arn" { value = module.foundation.kms_key_arn }
output "artifacts_bucket" { value = module.foundation.artifacts_bucket }
output "alb_logs_bucket" { value = module.foundation.alb_logs_bucket }
output "alarm_topic_arn" { value = module.foundation.alarm_topic_arn }
output "ci_plan_role_arn" { value = module.foundation.ci_plan_role_arn }
output "ci_apply_role_arn" { value = module.foundation.ci_apply_role_arn }
output "private_zone_id" { value = aws_route53_zone.private.zone_id }
output "private_zone_name" { value = var.private_zone_name }

output "networks" {
  value = {
    nonprod = {
      vpc_id            = module.network_nonprod.vpc_id
      cidr              = module.network_nonprod.cidr_block
      public_subnet_ids = module.network_nonprod.public_subnet_ids
      app_subnet_ids    = module.network_nonprod.app_subnet_ids
      data_subnet_ids   = module.network_nonprod.data_subnet_ids
      nat_public_ips    = module.network_nonprod.nat_public_ips
    }
    prod = {
      vpc_id            = module.network_prod.vpc_id
      cidr              = module.network_prod.cidr_block
      public_subnet_ids = module.network_prod.public_subnet_ids
      app_subnet_ids    = module.network_prod.app_subnet_ids
      data_subnet_ids   = module.network_prod.data_subnet_ids
      nat_public_ips    = module.network_prod.nat_public_ips
    }
  }
}
