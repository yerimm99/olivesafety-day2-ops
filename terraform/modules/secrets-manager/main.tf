locals {
  secret_full_name = "olivesafety/${var.environment}/${var.secret_name}"
}

resource "aws_secretsmanager_secret" "this" {
  name        = local.secret_full_name
  description = "Application secrets for ${var.project_name}-${var.environment}"

  recovery_window_in_days = 0

  tags = {
    Name = local.secret_full_name
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(var.secret_values)
}
