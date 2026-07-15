locals {
  teams_webhook_secret_name = "olivesafety/dev/teams-webhook"
  teams_alert_lambda_name   = "${var.project_name}-${var.environment}-teams-alert-forwarder"
  teams_alert_topic_name    = "${var.project_name}-${var.environment}-teams-alerts"
}

data "aws_secretsmanager_secret" "teams_webhook" {
  name = local.teams_webhook_secret_name
}

data "archive_file" "teams_alert_forwarder" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/teams-alert-forwarder/lambda_function.py"
  output_path = "${path.module}/.terraform/teams-alert-forwarder.zip"
}

resource "aws_sns_topic" "teams_alerts" {
  name = local.teams_alert_topic_name

  tags = {
    Name        = local.teams_alert_topic_name
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role" "teams_alert_forwarder" {
  name = "${local.teams_alert_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${local.teams_alert_lambda_name}-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "teams_alert_forwarder" {
  name = "${local.teams_alert_lambda_name}-policy"
  role = aws_iam_role.teams_alert_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadTeamsWebhookSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = data.aws_secretsmanager_secret.teams_webhook.arn
      }
    ]
  })
}

resource "aws_lambda_function" "teams_alert_forwarder" {
  function_name = local.teams_alert_lambda_name
  role          = aws_iam_role.teams_alert_forwarder.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.teams_alert_forwarder.output_path
  source_code_hash = data.archive_file.teams_alert_forwarder.output_base64sha256

  timeout     = 15
  memory_size = 128

  environment {
    variables = {
      TEAMS_WEBHOOK_SECRET_NAME = local.teams_webhook_secret_name
    }
  }

  tags = {
    Name        = local.teams_alert_lambda_name
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "teams_alert_forwarder" {
  topic_arn = aws_sns_topic.teams_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.teams_alert_forwarder.arn
}

resource "aws_lambda_permission" "allow_sns_teams_alerts" {
  statement_id  = "AllowExecutionFromTeamsAlertsSns"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.teams_alert_forwarder.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.teams_alerts.arn
}

output "teams_alert_sns_topic_arn" {
  description = "SNS topic ARN for Teams alert notifications"
  value       = aws_sns_topic.teams_alerts.arn
}

output "teams_alert_lambda_name" {
  description = "Lambda function name for Teams alert forwarding"
  value       = aws_lambda_function.teams_alert_forwarder.function_name
}
