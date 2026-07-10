resource "aws_sqs_queue" "order_events" {
  name                       = "olivesafety-day2-ops-dev-order-events"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600

  tags = {
    Name        = "olivesafety-day2-ops-dev-order-events"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_sns_topic" "order_events" {
  name = "olivesafety-day2-ops-dev-order-events"

  tags = {
    Name        = "olivesafety-day2-ops-dev-order-events"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "sqs_queue_url" {
  value = aws_sqs_queue.order_events.url
}

output "sns_topic_arn" {
  value = aws_sns_topic.order_events.arn
}
