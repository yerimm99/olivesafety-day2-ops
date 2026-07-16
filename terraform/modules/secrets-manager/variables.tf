variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "secret_name" {
  type    = string
  default = "api"
}

variable "secret_values" {
  description = "Secret values for application. Do not commit tfvars containing real values."
  type        = map(string)
  sensitive   = true
}
