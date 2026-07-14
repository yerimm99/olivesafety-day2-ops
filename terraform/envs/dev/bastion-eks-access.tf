resource "aws_iam_role_policy" "bastion_eks_describe" {
  name = "${var.project_name}-${var.environment}-bastion-eks-describe"
  role = module.bastion.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_access_entry" "bastion" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.bastion.iam_role_arn
  type          = "STANDARD"

  depends_on = [
    module.eks,
    module.bastion
  ]
}

resource "aws_eks_access_policy_association" "bastion_cluster_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.bastion.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.bastion
  ]
}
