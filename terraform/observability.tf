# EKS control-plane audit/API logs, CloudTrail API audit trail, scaling events.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
  tags              = local.common_tags
}
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-audit"
  force_destroy = var.cloudtrail_force_destroy
  tags          = local.common_tags
}
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expiration"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = var.cloudtrail_retention_days }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid = "CloudTrailAclCheck"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.name}-trail"]
    }
  }
  statement {
    sid = "CloudTrailPut"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.name}-trail"]
    }
  }
}
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}
resource "aws_cloudtrail" "audit" {
  name                          = "${local.name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.cloudtrail]
}
resource "aws_cloudwatch_event_rule" "node_scaling" {
  name        = "${local.name}-asg-scale-events"
  description = "ASG instances launched/terminated; not evidence of NodeReady"
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"],
    "detail-type" = ["EC2 Instance Launch Successful", "EC2 Instance Terminate Successful"],
    detail        = { AutoScalingGroupName = [local.managed_asg_name] }
  })
}
resource "aws_cloudwatch_event_target" "node_scaling" {
  rule = aws_cloudwatch_event_rule.node_scaling.name
  arn  = aws_sns_topic.infra_alerts.arn
}
resource "aws_sns_topic_policy" "infra_events" {
  arn = aws_sns_topic.infra_alerts.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "AllowEventBridge", Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.infra_alerts.arn, Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.node_scaling.arn } } },
    { Sid = "AllowCloudWatch", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.infra_alerts.arn, Condition = { "StringEquals" = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } } }
  ] })
}
