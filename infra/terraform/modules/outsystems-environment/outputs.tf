output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_zone_id" { value = aws_lb.this.zone_id }
output "url" { value = "https://${var.public_hostname}" }
output "controller_fqdn" {
  description = "Register this address in LifeTime (Environments > Register)."
  value       = local.controller_fqdn
}
output "controller_instance_id" { value = aws_instance.controller.id }
output "db_endpoint" { value = aws_db_instance.this.address }
output "platform_secret_arn" { value = aws_secretsmanager_secret.platform.arn }
output "frontend_asg_name" { value = try(aws_autoscaling_group.frontend[0].name, null) }
output "server_security_group_id" { value = aws_security_group.server.id }
output "web_acl_arn" { value = try(aws_wafv2_web_acl.this[0].arn, null) }
