# =============================================================================
# examples/minimal -- greenfield AWS account
#
# This is the simplest possible consumer of the baseline module: pass the two
# required inputs (alert_email + monthly_budget_usd), accept all defaults.
#
# Use this when:
#   - The AWS account has no pre-existing CloudTrail / GuardDuty / SecurityHub
#   - You're applying from a developer laptop or a simple CI runner
#   - You want the full baseline with no customization
#
# To apply:
#   1. Set AWS credentials in your shell (env vars, ~/.aws/credentials profile,
#      or AWS SSO -- whichever works for your team)
#   2. cp terraform.tfvars.example terraform.tfvars   # then edit values
#   3. terraform init
#   4. terraform plan -out=baseline.tfplan
#   5. terraform apply baseline.tfplan
#   6. Click the SNS subscription confirmation email AWS sends
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.42.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy the baseline into. Use your primary operational region."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address that receives all security + cost alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly AWS spend cap in USD. Alerts at 80% and 100%."
  type        = number
}

module "security_baseline" {
  source = "../../modules/baseline"

  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Module      = "aws-startup-security-baseline"
  }
}

output "sns_topic_arn" {
  value       = module.security_baseline.sns_topic_arn
  description = "Use this ARN if you want to subscribe additional endpoints (Slack webhook via Lambda, PagerDuty, etc.)."
}

output "cloudtrail_arn" {
  value = module.security_baseline.cloudtrail_arn
}

output "cloudtrail_log_group_name" {
  value       = module.security_baseline.cloudtrail_log_group_name
  description = "Use this for additional CloudWatch Logs metric filters."
}

output "next_steps" {
  value = <<-EOT
    Baseline applied. Now:
    1. Check ${var.alert_email} for an SNS subscription confirmation email -- click the link.
    2. Visit AWS Security Hub console to confirm AFSBP standard is subscribed.
    3. Visit GuardDuty console to confirm the detector is enabled.
    4. (Optional) Subscribe additional endpoints to ${module.security_baseline.sns_topic_arn}.
    5. Review findings in Security Hub after ~6-24 hours of data.
  EOT
}
