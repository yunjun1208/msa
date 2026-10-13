resource "aws_ecr_repository" "service" {
  for_each             = toset(["apigateway", "member-service", "ordering-service", "product-service", "frontend-service"])
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = local.common_tags
}
resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  vpc_id      = aws_vpc.main.id
  description = "MySQL only from EKS worker network"
  ingress {
    description     = "MySQL from EKS workloads"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  tags = local.common_tags
}
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = local.common_tags
}
resource "random_password" "db" {
  length  = 24
  special = false
}
resource "aws_db_instance" "mysql" {
  identifier              = "${local.name}-mysql"
  engine                  = "mysql"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = "ordermsa"
  username                = "admin"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = false # Lab cost optimization; production should enable Multi-AZ.
  backup_retention_period = 3
  skip_final_snapshot     = true # Lab use only.
  deletion_protection     = false
  tags                    = local.common_tags
}
resource "aws_s3_bucket" "images" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-${var.region}-images"
  force_destroy = false
  tags          = local.common_tags
}
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false # Existing frontend uses direct public S3 URLs.
  restrict_public_buckets = false
}
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_policy" "public_product_images" {
  bucket     = aws_s3_bucket.images.id
  depends_on = [aws_s3_bucket_public_access_block.images]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadProductsOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.images.arn}/products/*"
    }]
  })
}
resource "aws_sns_topic" "orders" {
  name = "${local.name}-order-events"
  tags = local.common_tags
}
resource "aws_sns_topic" "infra_alerts" {
  name = "${local.name}-infra-alerts"
  tags = local.common_tags
}
resource "aws_sns_topic_subscription" "infra_email" {
  count     = var.admin_alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.infra_alerts.arn
  protocol  = "email"
  endpoint  = var.admin_alert_email
}
resource "aws_sqs_queue" "order_dlq" {
  name                      = "${local.name}-order-alert-dlq"
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}
resource "aws_sqs_queue" "order" {
  name                       = "${local.name}-order-alert-queue"
  visibility_timeout_seconds = 180
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.order_dlq.arn, maxReceiveCount = 3 })
  tags                       = local.common_tags
}
resource "aws_sqs_queue_redrive_allow_policy" "order" {
  queue_url            = aws_sqs_queue.order_dlq.id
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.order.arn] })
}
resource "aws_sqs_queue_policy" "sns_send" {
  queue_url = aws_sqs_queue.order.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOnlyOrderTopic"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.order.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}
resource "aws_sns_topic_subscription" "order_to_queue" {
  topic_arn  = aws_sns_topic.orders.arn
  protocol   = "sqs"
  endpoint   = aws_sqs_queue.order.arn
  depends_on = [aws_sqs_queue_policy.sns_send]
}
resource "aws_cloudwatch_metric_alarm" "order_dlq" {
  alarm_name          = "${local.name}-order-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  dimensions          = { QueueName = aws_sqs_queue.order_dlq.name }
  alarm_actions       = [aws_sns_topic.infra_alerts.arn]
  treat_missing_data  = "notBreaching"
}
