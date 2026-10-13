variable "project_name" {
  description = "Resource prefix. Lowercase, use dashes, <= 16 chars."
  type        = string
  default     = "msa-final"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project_name))
    error_message = "Use 3-16 lowercase letters/digits/dashes."
  }
}
variable "region" {
  type    = string
  default = "ap-northeast-2"
}
variable "cluster_name" {
  type    = string
  default = "msa-final-eks"
}
variable "kubernetes_version" {
  type        = string
  description = "Verify EKS availability before apply"
  default     = "1.35"
}
variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "admin_cidrs" {
  description = "IPv4 CIDRs allowed to reach EKS API endpoint, e.g. public workstation IP /32"
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for x in var.admin_cidrs : can(cidrnetmask(x))])
    error_message = "Provide at least one IPv4 CIDR."
  }
}
variable "github_oidc_subject" {
  description = "Exact 'sub' from GitHub OIDC token. Repos from July 2026 may include immutable owner/repository IDs."
  type        = string
}
variable "existing_github_oidc_provider_arn" {
  description = "If an OIDC provider already exists, supply its ARN to avoid duplicate creation."
  type        = string
  default     = ""
}
variable "admin_alert_email" {
  type        = string
  description = "Optional email for infra alerts (requires subscription confirmation)."
  default     = ""
}

variable "domain_name" {
  type        = string
  description = "Public shopping site hostname e.g. shop.example.com (optional for infrastructure-only plan)."
  validation {
    condition     = length(var.domain_name) > 3 && can(regex("^[a-zA-Z0-9.-]+$", var.domain_name))
    error_message = "Provide a valid public hostname such as shop.example.com."
  }
}
variable "hosted_zone_id" {
  type        = string
  description = "Existing Route53 PUBLIC hosted zone ID for domain_name. Required to issue ACM certificate."
  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "Use an existing public Route53 hosted-zone ID."
  }
}
variable "ses_sender_email" {
  type        = string
  description = "SES sending address; must be verified before live email delivery."
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.ses_sender_email))
    error_message = "Provide an SES sender email address; mailbox verification is still required."
  }
}
variable "cloudtrail_retention_days" {
  type    = number
  default = 90
}

variable "cloudtrail_force_destroy" {
  description = "Allow permanent deletion of CloudTrail S3 objects during lab cleanup."
  type        = bool
  default     = false
}
