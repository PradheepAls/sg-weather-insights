resource "aws_route53_record" "public" {
  count   = var.public_zone_id == "" ? 0 : 1
  zone_id = var.public_zone_id
  name    = var.public_hostname
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# Stable private name for the controller: front-ends register against it and LifeTime
# targets it for deployments (it survives instance replacement).
resource "aws_route53_record" "controller" {
  zone_id = var.private_zone_id
  name    = local.controller_fqdn
  type    = "A"
  ttl     = 60
  records = [aws_instance.controller.private_ip]
}
