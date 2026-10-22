output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Platform Server instances)."
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs (RDS)."
  value       = aws_subnet.database[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways (outbound address of the platform servers)."
  value       = aws_eip.nat[*].public_ip
}
