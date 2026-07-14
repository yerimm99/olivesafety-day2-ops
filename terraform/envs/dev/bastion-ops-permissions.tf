resource "aws_iam_role_policy" "bastion_ops_readonly" {
  name = "${var.project_name}-${var.environment}-bastion-ops-readonly"
  role = module.bastion.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",

          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",

          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",

          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",

          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",

          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",

          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups",

          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListHealthChecks",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      }
    ]
  })
}
