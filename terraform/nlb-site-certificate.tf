# Supplementary HTTPS certificate for the NLB site hostname.
# Does not replace the existing aws-cisco.com ACM certificate.
locals {
  nlb_site_hostname = "server.${var.domain_name}"
}

resource "aws_acm_certificate" "nlb_site" {
  domain_name       = local.nlb_site_hostname
  validation_method = "DNS"
  tags              = local.common_tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "nlb_site_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.nlb_site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "nlb_site" {
  certificate_arn         = aws_acm_certificate.nlb_site.arn
  validation_record_fqdns = [for record in aws_route53_record.nlb_site_cert_validation : record.fqdn]
}

output "nlb_site_domain" {
  value = local.nlb_site_hostname
}
output "nlb_site_certificate_arn" {
  value = aws_acm_certificate_validation.nlb_site.certificate_arn
}
