terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
  # IMPORTANT: local state is intended for workshop use only.
  # Before team use, configure encrypted S3 backend + state locking.
}
provider "aws" {
  region = var.region
}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_caller_identity" "current" {}
locals {
  name        = var.project_name
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  common_tags = { Project = local.name, ManagedBy = "Terraform" }
}
