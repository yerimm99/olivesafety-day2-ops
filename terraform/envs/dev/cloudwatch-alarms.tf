variable "enable_alb_alarms" {
  description = "Whether to create ALB related CloudWatch alarms"
  type        = bool
  default     = false
}

variable "alb_arn_suffix" {
  description = "CloudWatch LoadBalancer dimension value, for example app/name/id"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "CloudWatch TargetGroup dimension value, for example targetgroup/name/id"
  type        = string
  default     = ""
}

locals {
  enable_alb_target_alarms = var.enable_alb_alarms && var.alb_arn_suffix != "" && var.target_group_arn_suffix != ""
}

resource "aws_cloudwatch_metric_alarm" "teams_alert_forwarder_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-teams-alert-forwarder-errors"
  alarm_description   = "Detects errors from the Teams alert forwarder Lambda."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 60

  dimensions = {
    FunctionName = aws_lambda_function.teams_alert_forwarder.function_name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.teams_alerts.arn]
  ok_actions    = [aws_sns_topic.teams_alerts.arn]

  tags = {
    Name        = "${var.project_name}-${var.environment}-teams-alert-forwarder-errors"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = local.enable_alb_target_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-unhealthy-targets"
  alarm_description   = "Detects unhealthy ALB target count for olivesafety-api."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"
  period      = 60

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.teams_alerts.arn]
  ok_actions    = [aws_sns_topic.teams_alerts.arn]

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-unhealthy-targets"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = local.enable_alb_target_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-target-5xx"
  alarm_description   = "Detects HTTP 5xx responses returned by ALB targets."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.teams_alerts.arn]
  ok_actions    = [aws_sns_topic.teams_alerts.arn]

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-target-5xx"
    Project     = var.project_name
    Environment = var.environment
  }
}
