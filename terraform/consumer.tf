# Order notification Lambda: SQS -> SESv2 transactional email.
# Sender verification and recipient sandbox rules remain AWS-side prerequisites.
data "archive_file" "consumer" {
  type        = "zip"
  source_file = "${path.module}/lambda/order_notifications/index.mjs"
  output_path = "${path.module}/lambda/order_notifications/consumer.zip"
}
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "notification_lambda" {
  name               = "${local.name}-notification-consumer"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.notification_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "read-notification-queue"
  role = aws_iam_role.notification_lambda.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.order.arn }]
  })
}
resource "aws_lambda_function" "order_notification" {
  filename         = data.archive_file.consumer.output_path
  function_name    = "${local.name}-order-notification"
  role             = aws_iam_role.notification_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 15
  source_code_hash = data.archive_file.consumer.output_base64sha256
  environment { variables = { SES_SENDER_EMAIL = var.ses_sender_email } }
  depends_on = [aws_iam_role_policy_attachment.lambda_basic, aws_iam_role_policy.lambda_sqs, aws_iam_role_policy.lambda_ses]

}
resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn        = aws_sqs_queue.order.arn
  function_name           = aws_lambda_function.order_notification.arn
  batch_size              = 1
  enabled                 = true
  function_response_types = ["ReportBatchItemFailures"]
}

# SES verification requires mailbox confirmation. Sandbox accounts may only send to verified recipients.
resource "aws_ses_email_identity" "sender" {
  count = var.ses_sender_email != "" ? 1 : 0
  email = var.ses_sender_email
}
resource "aws_iam_role_policy" "lambda_ses" {
  name = "send-order-email"
  role = aws_iam_role.notification_lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["ses:SendEmail"],
    Resource = var.ses_sender_email != "" ? ["arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_sender_email}"] : ["*"]
  }] })
}
