output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "cluster_role_arn" {
  value = aws_iam_role.cluster.arn
}

output "oidc_provider_url" {
  value = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}
