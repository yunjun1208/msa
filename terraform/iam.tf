data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "product" {
  name               = "${local.name}-product-pod"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}
resource "aws_iam_role_policy" "product_s3" {
  name = "product-images"
  role = aws_iam_role.product.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.images.arn}/products/*" },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.images.arn, Condition = { StringLike = { "s3:prefix" = ["products/*"] } } }
    ]
  })
}
resource "aws_eks_pod_identity_association" "product" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "soldesk"
  service_account = "product-sa"
  role_arn        = aws_iam_role.product.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.product_s3]
}
resource "aws_iam_role" "ordering" {
  name               = "${local.name}-ordering-pod"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}
resource "aws_iam_role_policy" "ordering_sns" {
  name = "publish-order-topic"
  role = aws_iam_role.ordering.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.orders.arn }]
  })
}
resource "aws_eks_pod_identity_association" "ordering" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "soldesk"
  service_account = "ordering-sa"
  role_arn        = aws_iam_role.ordering.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.ordering_sns]
}
# OIDC is for GitHub Actions only; EKS Pod Identity is a separate mechanism.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == "" ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  github_oidc_arn = var.existing_github_oidc_provider_arn != "" ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.github_oidc_subject]
    }
  }
}
resource "aws_iam_role" "github" {
  name               = "${local.name}-github-ecr"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}
resource "aws_iam_role_policy" "github_ecr" {
  role = aws_iam_role.github.id
  name = "ecr-push-five-services"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "ecr:BatchGetImage"], Resource = [for repo in aws_ecr_repository.service : repo.arn] }
    ]
  })
}
