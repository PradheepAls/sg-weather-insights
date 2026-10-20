output "url" {
  description = "Point your DNS record (or browser) at this ALB name."
  value       = "https://${aws_lb.this.dns_name}"
}

output "controller_private_ip" {
  description = "Register this environment in LifeTime with this address."
  value       = aws_instance.controller.private_ip
}

output "controller_instance_id" {
  description = "Connect with: aws ssm start-session --target <id>"
  value       = aws_instance.controller.id
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "platform_secret_arn" {
  value = aws_secretsmanager_secret.platform.arn
}
