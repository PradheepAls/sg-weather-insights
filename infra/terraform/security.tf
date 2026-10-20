# Traffic path: clients -> ALB (443) -> servers (443) -> SQL Server (1433). Nothing else in.
# No RDP/SSH anywhere: admins use SSM Session Manager.

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB"
  vpc_id      = aws_vpc.this.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description = "HTTP(S) from allowed clients"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.alb_ingress_cidrs
    }
  }

  egress {
    description = "HTTPS to servers"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_security_group" "server" {
  name        = "${local.name}-server"
  description = "OutSystems controller and front-ends"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Between servers of the same farm: OutSystems services (12000-12004) and the cache
  # invalidation service (RabbitMQ 5672) on the controller.
  ingress {
    description = "OutSystems platform services within the farm"
    from_port   = 12000
    to_port     = 12004
    protocol    = "tcp"
    self        = true
  }
  ingress {
    description = "Cache invalidation (RabbitMQ) within the farm"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "HTTPS out via NAT: installers, Windows Update, data.gov.sg, AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "HTTP out for certificate revocation checks"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "SQL Server (RDS lives in the private subnets)"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "OutSystems platform services within the farm"
    from_port   = 12000
    to_port     = 12004
    protocol    = "tcp"
    self        = true
  }
  egress {
    description = "Cache invalidation (RabbitMQ) within the farm"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    self        = true
  }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "SQL Server, only from the OutSystems servers"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SQL Server from servers"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.server.id]
  }
}
