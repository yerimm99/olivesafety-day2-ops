variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "olivesafety-day2-ops"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "secret_values" {
  description = "Secret values for olivesafety api. Use local terraform.tfvars only."
  type        = map(string)
  sensitive   = true
}
