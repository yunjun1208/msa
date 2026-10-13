output "cluster_name" { value = aws_eks_cluster.main.name }
output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "ecr_repositories" { value = { for k, v in aws_ecr_repository.service : k => v.repository_url } }
output "db_host" { value = aws_db_instance.mysql.address }
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
output "product_image_bucket" { value = aws_s3_bucket.images.id }
output "order_events_topic_arn" { value = aws_sns_topic.orders.arn }
output "order_queue_url" { value = aws_sqs_queue.order.id }
output "order_dead_letter_queue_url" { value = aws_sqs_queue.order_dlq.id }
output "github_actions_role_arn" { value = aws_iam_role.github.arn }

output "aws_account_id" { value = data.aws_caller_identity.current.account_id }
output "aws_region" { value = var.region }
output "ses_sender_email" { value = var.ses_sender_email }
output "alb_controller_role_arn" { value = aws_iam_role.alb_controller.arn }
output "external_dns_role_arn" { value = aws_iam_role.external_dns.arn }
output "autoscaler_role_arn" { value = aws_iam_role.autoscaler.arn }
output "alertmanager_role_arn" { value = aws_iam_role.alertmanager.arn }
output "acm_certificate_arn" { value = var.domain_name != "" ? aws_acm_certificate_validation.site[0].certificate_arn : "" }
output "site_domain" { value = var.domain_name }
output "infra_alerts_sns_arn" { value = aws_sns_topic.infra_alerts.arn }
