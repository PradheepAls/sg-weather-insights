output "vpc_id" { value = aws_vpc.this.id }
output "cidr_block" { value = aws_vpc.this.cidr_block }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "app_subnet_ids" { value = aws_subnet.app[*].id }
output "data_subnet_ids" { value = aws_subnet.data[*].id }
output "app_route_table_ids" { value = aws_route_table.app[*].id }
output "data_route_table_id" { value = aws_route_table.data.id }
output "nat_public_ips" {
  description = "Egress IPs; give these to any upstream that needs allow-listing."
  value       = aws_eip.nat[*].public_ip
}
