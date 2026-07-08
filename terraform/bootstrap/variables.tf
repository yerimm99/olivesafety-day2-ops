variable "aws_region" {
  description = "AWS region for Terraform backend resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used for backend resource naming"
  type        = string
  default     = "olivesafety-day2-ops"
}
