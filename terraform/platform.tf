# EKS platform add-ons use Pod Identity roles, not static AWS credentials.
# LBC IAM policy is pinned to the official v2.14.1 release documentation.
data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json"
}
resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name}-alb-controller"
  policy = data.http.alb_controller_policy.response_body
}
resource "aws_iam_role" "alb_controller" {
  name               = "${local.name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy_attachment.alb_controller]
}

resource "aws_iam_role" "external_dns" {
  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "external_dns" {
  name = "route53-zone-records"
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.external_dns]
}

resource "aws_iam_role" "autoscaler" {
  name               = "${local.name}-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}
resource "aws_iam_role_policy" "autoscaler" {
  name = "autoscaler-cluster-limited"
  role = aws_iam_role.autoscaler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeScalingActivities", "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeTags", "ec2:DescribeImages", "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplateVersions", "ec2:GetInstanceTypesFromInstanceRequirements", "eks:DescribeNodegroup"], Resource = "*" },
      { Effect = "Allow", Action = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"], Resource = "*", Condition = { StringEquals = { "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned", "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled" = "true" } } }
    ]
  })
}
resource "aws_eks_pod_identity_association" "autoscaler" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.autoscaler.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.autoscaler]
}
# EKS Managed Node Group tags do not automatically propagate to its underlying ASG.
locals {
  managed_asg_name = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name
}
resource "aws_autoscaling_group_tag" "discovery_enabled" {
  autoscaling_group_name = local.managed_asg_name
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}
resource "aws_autoscaling_group_tag" "discovery_cluster" {
  autoscaling_group_name = local.managed_asg_name
  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

resource "aws_iam_role" "alertmanager" {
  name               = "${local.name}-alertmanager"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}
resource "aws_iam_role_policy" "alertmanager" {
  name = "publish-infra-alerts"
  role = aws_iam_role.alertmanager.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.infra_alerts.arn }
  ] })
}
resource "aws_eks_pod_identity_association" "alertmanager" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "monitoring"
  service_account = "alertmanager"
  role_arn        = aws_iam_role.alertmanager.arn
  depends_on      = [aws_eks_addon.pod_identity_agent, aws_iam_role_policy.alertmanager]
}

# Use an existing public hosted zone. Cert requires successful DNS validation.
resource "aws_acm_certificate" "site" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.site[0].domain_validation_options : dvo.domain_name => {
      name = dvo.resource_record_name, record = dvo.resource_record_value, type = dvo.resource_record_type
    }
  } : {}
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  records         = [each.value.record]
  type            = each.value.type
  ttl             = 60
  allow_overwrite = true
}
resource "aws_acm_certificate_validation" "site" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
