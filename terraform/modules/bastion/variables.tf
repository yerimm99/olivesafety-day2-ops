variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for bastion security group"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for bastion instance"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to access bastion via SSH"
  type        = string
}

variable "public_key_path" {
  description = "Local SSH public key path"
  type        = string
}

variable "instance_type" {
  description = "Bastion instance type"
  type        = string
  default     = "t3.micro"
}
