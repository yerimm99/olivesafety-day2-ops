output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "public_dns" {
  value = aws_instance.this.public_dns
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}

output "iam_role_arn" {
  value = aws_iam_role.this.arn
}
