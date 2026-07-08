output "terraform_state_bucket" {
  description = "S3 bucket name for Terraform remote state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}
