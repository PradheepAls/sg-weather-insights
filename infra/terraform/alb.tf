resource "aws_lb" "this" {
  name                       = local.name
  load_balancer_type         = "application"
  internal                   = var.alb_internal
  subnets                    = var.alb_internal ? aws_subnet.private[*].id : aws_subnet.public[*].id
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  idle_timeout               = 120 # long-running Service Center operations
  enable_deletion_protection = var.is_production
}

resource "aws_lb_target_group" "servers" {
  name     = "${local.name}-servers"
  port     = 443
  protocol = "HTTPS" # TLS all the way to IIS (self-signed inside the VPC)
  vpc_id   = aws_vpc.this.id

  health_check {
    path     = "/lb-health.html" # created by bootstrap; point at the app's own page once deployed
    protocol = "HTTPS"
    matcher  = "200"
  }
}

# Without a separate farm the controller serves user traffic; with a farm it does not, so
# compilations never slow down users.
resource "aws_lb_target_group_attachment" "controller" {
  count            = local.has_farm ? 0 : 1
  target_group_arn = aws_lb_target_group.servers.arn
  target_id        = aws_instance.controller.id
  port             = 443
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.servers.arn
  }
}

# Service Center, LifeTime and test endpoints: allowed from admin networks, 403 for everyone else.
resource "aws_lb_listener_rule" "admin_allow" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern { values = local.admin_paths }
  }
  condition {
    source_ip { values = var.admin_cidrs }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.servers.arn
  }
}

resource "aws_lb_listener_rule" "admin_deny" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  condition {
    path_pattern { values = local.admin_paths }
  }

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}
