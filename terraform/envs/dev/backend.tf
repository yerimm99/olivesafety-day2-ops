terraform {
  backend "s3" {
    bucket       = "olivesafety-day2-ops-191524136560-ap-northeast-2-tfstate"
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
