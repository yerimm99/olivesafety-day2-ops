locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  cluster_name       = local.cluster_name
  enable_nat_gateway = false
}

module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "secrets_manager" {
  source = "../../modules/secrets-manager"

  project_name  = var.project_name
  environment   = var.environment
  secret_name   = "api"
  secret_values = var.secret_values
}

output "api_secret_name" {
  value = module.secrets_manager.secret_name
}

output "api_secret_arn" {
  value = module.secrets_manager.secret_arn
}

module "external_secrets_irsa" {
  source = "../../modules/external-secrets-irsa"

  project_name = var.project_name
  environment  = var.environment

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  secret_arn = module.secrets_manager.secret_arn
}

module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_name    = local.cluster_name
  cluster_version = "1.34"

  cluster_subnet_ids = concat(
    module.vpc.public_subnet_ids,
    module.vpc.private_subnet_ids
  )

  # 비용 절감을 위해 dev 검증 환경은 public subnet에 node 배치
  # 운영 기준 설계에서는 private subnet + NAT/VPC Endpoint 구조로 확장
  node_subnet_ids = module.vpc.public_subnet_ids

  node_instance_types = ["t3.medium"]
  node_desired_size   = 1
  node_min_size       = 1
  node_max_size       = 2
}

module "alb_controller" {
  source = "../../modules/alb-controller"

  project_name = var.project_name
  environment  = var.environment

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "cluster_name" {
  value = local.cluster_name
}

output "ecr_repository_name" {
  value = module.ecr.repository_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "alb_controller_role_arn" {
  value = module.alb_controller.role_arn
}

output "external_secrets_role_arn" {
  value = module.external_secrets_irsa.role_arn
}
