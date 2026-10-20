module "foundation" {
  source            = "../../modules/foundation"
  name              = var.project
  alarm_emails      = var.alarm_emails
  github_repository = var.github_repository
}

module "network_nonprod" {
  source             = "../../modules/network"
  name               = "${var.project}-nonprod"
  cidr_block         = var.nonprod_cidr
  azs                = var.azs
  nat_gateway_per_az = false
  kms_key_arn        = module.foundation.kms_key_arn
  tags               = { Network = "nonprod" }
}

module "network_prod" {
  source             = "../../modules/network"
  name               = "${var.project}-prod"
  cidr_block         = var.prod_cidr
  azs                = var.azs
  nat_gateway_per_az = true # AZ-independent egress so ingestion survives an AZ outage
  kms_key_arn        = module.foundation.kms_key_arn
  tags               = { Network = "prod" }
}

# LifeTime (non-prod VPC) must reach the Prod controller to deploy. Peering is enough for two
# VPCs; move to Transit Gateway if more accounts/VPCs join.
resource "aws_vpc_peering_connection" "nonprod_prod" {
  vpc_id      = module.network_nonprod.vpc_id
  peer_vpc_id = module.network_prod.vpc_id
  auto_accept = true
  tags        = { Name = "${var.project}-nonprod-prod" }
}

resource "aws_route" "nonprod_to_prod" {
  count                     = length(module.network_nonprod.app_route_table_ids)
  route_table_id            = module.network_nonprod.app_route_table_ids[count.index]
  destination_cidr_block    = var.prod_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.nonprod_prod.id
}

resource "aws_route" "prod_to_nonprod" {
  count                     = length(module.network_prod.app_route_table_ids)
  route_table_id            = module.network_prod.app_route_table_ids[count.index]
  destination_cidr_block    = var.nonprod_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.nonprod_prod.id
}

resource "aws_route53_zone" "private" {
  name    = var.private_zone_name
  comment = "Controller records for every OutSystems environment"
  vpc {
    vpc_id = module.network_nonprod.vpc_id
  }
  vpc {
    vpc_id = module.network_prod.vpc_id
  }
}
