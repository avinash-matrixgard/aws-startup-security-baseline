# =============================================================================
# examples/with-existing-cloudtrail -- brownfield deployment
#
# Use this when your AWS account already has a multi-region CloudTrail trail
# (e.g., one configured by your auditor, by AWS Control Tower, or by a prior
# IaC stack).
#
# Setting create_cloudtrail = false:
#   - Skips trail / KMS key / S3 bucket creation
#   - Also skips the CloudTrail-derived alarms (root usage, console-no-MFA,
#     trail tampering) because those depend on our own CloudWatch Log Group
#
# If you want those alarms but keep your existing trail, the cleanest path
# is to add a CloudWatch Logs delivery to your existing trail (out of scope
# for this example) and forward selected metric filters to the SNS topic
# this module creates.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address for security + cost alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly AWS spend cap in USD."
  type        = number
}

module "security_baseline" {
  source = "../../modules/baseline"

  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd

  # KEY DIFFERENCE from minimal example: skip our trail
  create_cloudtrail = false

  # Disabling the trail also implicitly disables 3 CloudTrail-derived alarms
  # (root usage, console-without-MFA, trail tampering). If you need those,
  # see comments at the top of this file.

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

output "sns_topic_arn" {
  value = module.security_baseline.sns_topic_arn
}

output "guardduty_detector_id" {
  value = module.security_baseline.guardduty_detector_id
}

output "what_was_skipped" {
  value = <<-EOT
    Because create_cloudtrail = false, the following resources were NOT created:
      - aws_cloudtrail (use your existing trail)
      - aws_s3_bucket for trail logs
      - aws_kms_key for trail encryption
      - aws_cloudwatch_log_group for trail (and the 3 metric-filter alarms)
      - aws_iam_role/policy for CloudTrail-to-CloudWatch delivery

    Everything else (GuardDuty, Security Hub, Access Analyzer, Config, password
    policy, S3 public access block, EBS encryption, VPC flow logs, Cost
    Anomaly, Budgets, SNS topic + email subscription) was created normally.
  EOT
}
