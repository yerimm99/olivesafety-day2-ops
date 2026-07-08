output "db_instance_identifier" {
  value = aws_db_instance.this.identifier
}

output "db_address" {
  value = aws_db_instance.this.address
}

output "db_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}
