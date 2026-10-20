# ---------------------------------------------------------------- ALB

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB for ${local.name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = { for pair in setproduct(var.alb_ingress_cidrs, [80, 443]) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.alb.id
  description       = "HTTP(S) from allowed clients"
  ip_protocol       = "tcp"
  from_port         = each.value[1]
  to_port           = each.value[1]
  cidr_ipv4         = each.value[0]
}

resource "aws_vpc_security_group_egress_rule" "alb_to_servers" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTPS to OutSystems servers"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.server.id
}

# ---------------------------------------------------------------- servers

resource "aws_security_group" "server" {
  name        = "${local.name}-server"
  description = "OutSystems controller and front-ends for ${local.name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-server" })
}

resource "aws_vpc_security_group_ingress_rule" "server_from_alb" {
  security_group_id            = aws_security_group.server.id
  description                  = "HTTPS from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "server_from_lifetime" {
  count             = local.is_lifetime ? 0 : 1
  security_group_id = aws_security_group.server.id
  description       = "LifeTime to Service Center"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.lifetime_cidr
}

resource "aws_vpc_security_group_ingress_rule" "server_internal" {
  for_each                     = { for p in local.platform_ports : "${p.from}-${p.to}" => p }
  security_group_id            = aws_security_group.server.id
  description                  = each.value.desc
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.server.id
}

resource "aws_vpc_security_group_ingress_rule" "server_https_internal" {
  security_group_id            = aws_security_group.server.id
  description                  = "HTTPS between servers in the farm"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.server.id
}

# Egress: HTTPS anywhere (installer download, data.gov.sg, Forge, AWS endpoints), SQL to the DB,
# and the intra-farm ports. No RDP/SSH anywhere: access is via SSM Session Manager.
resource "aws_vpc_security_group_egress_rule" "server_https" {
  security_group_id = aws_security_group.server.id
  description       = "HTTPS egress"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "server_http" {
  security_group_id = aws_security_group.server.id
  description       = "HTTP egress for Windows Update CRL/OCSP checks"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "server_to_db" {
  security_group_id            = aws_security_group.server.id
  description                  = "SQL Server"
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_vpc_security_group_egress_rule" "server_internal" {
  for_each                     = { for p in local.platform_ports : "${p.from}-${p.to}" => p }
  security_group_id            = aws_security_group.server.id
  description                  = each.value.desc
  ip_protocol                  = "tcp"
  from_port                    = each.value.from
  to_port                      = each.value.to
  referenced_security_group_id = aws_security_group.server.id
}

# ---------------------------------------------------------------- database

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "RDS SQL Server for ${local.name}; reachable only from its own servers"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-db" })
}

resource "aws_vpc_security_group_ingress_rule" "db_from_servers" {
  security_group_id            = aws_security_group.db.id
  description                  = "SQL Server from OutSystems servers"
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
  referenced_security_group_id = aws_security_group.server.id
}
