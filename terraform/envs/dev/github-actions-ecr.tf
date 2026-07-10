data "aws_caller_identity" "github_actions" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name        = "github-actions-oidc"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  name = "olivesafety-day2-ops-dev-github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:yerimm99/olivesafety-day2-ops:ref:refs/heads/*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "olivesafety-day2-ops-dev-github-actions-ecr-role"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "olivesafety-day2-ops-dev-github-actions-ecr-policy"
  description = "Allow GitHub Actions to push Docker images to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEcrAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = module.ecr.repository_arn
      }
    ]
  })

  tags = {
    Name        = "olivesafety-day2-ops-dev-github-actions-ecr-policy"
    Project     = "olivesafety-day2-ops"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}

output "github_actions_ecr_role_arn" {
  value = aws_iam_role.github_actions_ecr.arn
}
