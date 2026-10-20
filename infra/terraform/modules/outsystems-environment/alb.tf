resource "aws_lb" "this" {
  name                       = local.name
  load_balancer_type         = "application"
  internal                   = var.alb_internal
  subnets                    = var.alb_internal ? var.app_subnet_ids : var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  idle_timeout               = 120 # long-running Service Center / LifeTime operations
  enable_deletion_protection = var.is_production

  access_logs {
    bucket  = var.alb_logs_bucket
    prefix  = local.name
    enabled = true
  }

  tags = local.tags
}

resource "aws_lb_target_group" "servers" {
  name                 = "${local.name}-servers"
  port                 = 443
  protocol             = "HTTPS" # end-to-end TLS; IIS uses a self-signed cert inside the VPC
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 60

  health_check {
    path                = var.health_check_path
    protocol            = "HTTPS"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

# In non-prod (and LifeTime) the controller also serves traffic. In Prod it does not, so a
# compilation spike on the controller never affects end users.
resource "aws_lb_target_group_attachment" "controller" {
  count            = var.dedicated_controller ? 0 : 1
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

# Platform consoles and test tooling only from admin networks; everyone else gets 403.
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
