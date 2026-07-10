data "aws_caller_identity" "app_irsa_current" {}

data "aws_eks_cluster" "app_irsa" {
  name = "olivesafety-day2-ops-dev-eks"

  depends_on = [
    module.eks
  ]
}

data "aws_iam_openid_connect_provider" "app_irsa" {
  url = data.aws_eks_cluster.app_irsa.identity[0].oidc[0].issuer

  depends_on = [
    module.eks
  ]
}

locals {
  app_irsa_oidc_provider = replace(data.aws_eks_cluster.app_irsa.identity[0].oidc[0].issuer, "https://", "")
}

resource "aws_iam_role" "olivesafety_api" {
  name = "olivesafety-day2-ops-dev-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.app_irsa.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.app_irsa_oidc_provider}:aud" = "sts.amazonaws.com"
            "${local.app_irsa_oidc_provider}:sub" = "system:serviceaccount:olivesafety:olivesafety-api-sa"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "olivesafety-day2-ops-dev-api-role"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_policy" "olivesafety_api" {
  name        = "olivesafety-day2-ops-dev-api-policy"
  description = "Allow olivesafety API pods to access SQS and SNS in dev"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSqsAccess"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:SendMessage"
        ]
        Resource = "arn:aws:sqs:ap-northeast-2:${data.aws_caller_identity.app_irsa_current.account_id}:*"
      },
      {
        Sid    = "AllowSnsPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "arn:aws:sns:ap-northeast-2:${data.aws_caller_identity.app_irsa_current.account_id}:*"
      }
    ]
  })

  tags = {
    Name        = "olivesafety-day2-ops-dev-api-policy"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "olivesafety_api" {
  role       = aws_iam_role.olivesafety_api.name
  policy_arn = aws_iam_policy.olivesafety_api.arn
}

output "api_irsa_role_arn" {
  value = aws_iam_role.olivesafety_api.arn
}
