# =============================================================================
# Required inputs
# =============================================================================

variable "alert_email" {
  description = <<-EOT
    Email address to receive security + cost alerts (CloudWatch alarms,
    GuardDuty findings, Cost Anomaly Detection, Budgets thresholds). A single
    SNS topic is created and this address is subscribed to it.

    AWS will send a confirmation email after the first apply -- you must click
    the link in that email or you will not receive any alerts. Check spam.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address (e.g., security@yourstartup.com)."
  }
}

variable "monthly_budget_usd" {
  description = <<-EOT
    Monthly AWS spend cap in USD. AWS Budgets sends an alert at 80% (warning)
    and 100% (critical) of this value to the SNS topic configured above.

    Set this to your honest expected monthly spend ceiling, not an aspirational
    one. The point is to catch surprise bills early -- if you set it 5x your
    real spend, you will never get an alert until you have already lost the
    runway month.
  EOT
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than 0."
  }
}

# =============================================================================
# Naming + tagging
# =============================================================================

variable "name_prefix" {
  description = "Prefix prepended to all created resources. Lowercase, hyphens allowed. Useful for multi-deployment or matching org naming conventions."
  type        = string
  default     = "security-baseline"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric/hyphens, start with a letter, and be <=31 chars."
  }
}

variable "tags" {
  description = "Tags applied to every resource this module creates. Merged with module-internal tags ('Module' and 'Source')."
  type        = map(string)
  default     = {}
}

# =============================================================================
# IAM password policy (Control 1)
# =============================================================================

variable "password_min_length" {
  description = "Minimum password length. NIST 800-63B current guidance is >=8; we default to 14 because seed-stage password reuse is rampant and 14 chars hardens against credential stuffing."
  type        = number
  default     = 14

  validation {
    condition     = var.password_min_length >= 8 && var.password_min_length <= 128
    error_message = "password_min_length must be between 8 and 128 (AWS hard limits)."
  }
}

variable "password_max_age_days" {
  description = <<-EOT
    Password max age in days. NIST 800-63B no longer recommends periodic
    rotation in the absence of compromise -- but PCI-DSS, ISO 27001, and
    RBI Master Direction still expect <=365 day rotation. We default to 365
    to satisfy both.

    Set to 0 to disable rotation entirely if your compliance framework allows.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.password_max_age_days >= 0 && var.password_max_age_days <= 1095
    error_message = "password_max_age_days must be between 0 (no rotation) and 1095 (3 years)."
  }
}

variable "password_reuse_prevention" {
  description = "Number of previous passwords AWS remembers and prevents reuse of. Default 24 matches CIS Benchmark."
  type        = number
  default     = 24

  validation {
    condition     = var.password_reuse_prevention >= 0 && var.password_reuse_prevention <= 24
    error_message = "password_reuse_prevention must be between 0 and 24 (AWS hard limits)."
  }
}

# =============================================================================
# CloudTrail (Control 3)
# =============================================================================

variable "trail_name" {
  description = "Name of the CloudTrail trail. If empty, defaults to '{name_prefix}-trail'."
  type        = string
  default     = ""
}

variable "cloudtrail_log_retention_days" {
  description = <<-EOT
    Number of days to retain CloudTrail logs in S3 before deletion. Default
    365 covers most compliance windows (PCI-DSS = 1 year, SOC 2 = 1 year,
    RBI = 1 year for IT logs, GDPR has no fixed minimum but 1 year is
    industry norm).

    Set to 0 to keep logs forever (cheaper than you think -- logs are
    auto-tiered to Glacier Deep Archive at 90 days).
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.cloudtrail_log_retention_days >= 0 && var.cloudtrail_log_retention_days <= 3650
    error_message = "cloudtrail_log_retention_days must be between 0 (forever) and 3650 (10 years)."
  }
}

variable "create_cloudtrail" {
  description = "Whether to create a CloudTrail trail. Set to false if your account already has a multi-region trail (use the with-existing-cloudtrail example)."
  type        = bool
  default     = true
}

# =============================================================================
# GuardDuty (Control 5)
# =============================================================================

variable "enable_guardduty" {
  description = "Whether to enable GuardDuty in the current region."
  type        = bool
  default     = true
}

variable "guardduty_finding_frequency" {
  description = "How often GuardDuty publishes findings to CloudWatch Events. Valid: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS. Default FIFTEEN_MINUTES (fastest detection)."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "guardduty_finding_frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

# =============================================================================
# Security Hub (Control 6)
# =============================================================================

variable "enable_security_hub" {
  description = "Whether to enable Security Hub and subscribe to AWS Foundational Best Practices. CIS / PCI / NIST standards remain off by default to keep finding noise low."
  type        = bool
  default     = true
}

# =============================================================================
# AWS Config (Control 10)
# =============================================================================

variable "enable_config_recorder" {
  description = "Whether to enable an AWS Config recorder. We restrict to high-blast-radius resource types by default (see config_record_all)."
  type        = bool
  default     = true
}

variable "config_record_all" {
  description = <<-EOT
    If true, AWS Config records every supported resource type (~$10-30/month
    at startup scale). If false (default), records only IAM, S3 buckets,
    security groups, and NACLs (~$2/month at startup scale). The restricted
    set covers the resource types that matter most for security incident
    investigation.
  EOT
  type        = bool
  default     = false
}

variable "config_recorded_resource_types" {
  description = "Resource types recorded by AWS Config when config_record_all = false. Default covers IAM, S3, network ACLs, security groups."
  type        = list(string)
  default = [
    "AWS::IAM::User",
    "AWS::IAM::Role",
    "AWS::IAM::Policy",
    "AWS::IAM::Group",
    "AWS::S3::Bucket",
    "AWS::EC2::SecurityGroup",
    "AWS::EC2::NetworkAcl",
    "AWS::EC2::VPC",
    "AWS::KMS::Key",
  ]
}

# =============================================================================
# VPC Flow Logs (Control 9)
# =============================================================================

variable "enable_default_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs on the default VPC. If you operate exclusively in custom VPCs, set this to false and configure flow logs on those VPCs separately."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC Flow Logs in CloudWatch Logs."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a valid CloudWatch Logs retention value: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653."
  }
}

# =============================================================================
# Cost monitoring (Controls 11 + 12)
# =============================================================================

variable "enable_cost_anomaly_detection" {
  description = "Whether to create an AWS Cost Anomaly Detection monitor + subscription emailing alert_email."
  type        = bool
  default     = true
}

variable "cost_anomaly_threshold_usd" {
  description = "Minimum USD impact for an anomaly to trigger an email. Lower = noisier. Default 100 catches material spikes for early-stage spend; raise to 500-1000 once you're at >$10k/mo spend."
  type        = number
  default     = 100

  validation {
    condition     = var.cost_anomaly_threshold_usd >= 1
    error_message = "cost_anomaly_threshold_usd must be at least 1."
  }
}

variable "budget_alert_thresholds_pct" {
  description = "Percentage thresholds at which AWS Budgets sends alerts. Default [80, 100]: warning at 80% spend, critical at 100%."
  type        = list(number)
  default     = [80, 100]

  validation {
    condition     = alltrue([for t in var.budget_alert_thresholds_pct : t > 0 && t <= 200])
    error_message = "Each threshold must be between 1 and 200."
  }
}
