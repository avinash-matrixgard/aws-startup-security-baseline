# =============================================================================
# Outputs -- useful ARNs and resource identifiers for downstream automation
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives all security + cost alerts. Subscribe additional endpoints (Slack webhook, PagerDuty, etc.) to this if you outgrow email-only delivery."
  value       = aws_sns_topic.alerts.arn
}

output "cloudtrail_arn" {
  description = "ARN of the multi-region CloudTrail trail (null if create_cloudtrail = false)."
  value       = var.create_cloudtrail ? aws_cloudtrail.this[0].arn : null
}

output "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch Log Group that mirrors CloudTrail events. Use this for additional metric filters or log queries."
  value       = var.create_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudtrail_s3_bucket" {
  description = "Name of the S3 bucket where CloudTrail stores logs."
  value       = var.create_cloudtrail ? aws_s3_bucket.trail[0].id : null
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key encrypting CloudTrail logs."
  value       = var.create_cloudtrail ? aws_kms_key.cloudtrail[0].arn : null
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector (null if enable_guardduty = false)."
  value       = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "security_hub_enabled" {
  description = "Whether Security Hub is enabled in this account."
  value       = var.enable_security_hub
}

output "access_analyzer_arn" {
  description = "ARN of the IAM Access Analyzer (account scope)."
  value       = aws_accessanalyzer_analyzer.this.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config recorder (null if enable_config_recorder = false)."
  value       = var.enable_config_recorder ? aws_config_configuration_recorder.this[0].name : null
}

output "config_s3_bucket" {
  description = "Name of the S3 bucket where AWS Config stores configuration snapshots."
  value       = var.enable_config_recorder ? aws_s3_bucket.config[0].id : null
}

output "monthly_budget_name" {
  description = "Name of the AWS Budgets monthly cap budget."
  value       = aws_budgets_budget.monthly_cap.name
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch Log Group receiving default-VPC flow logs (null if disabled)."
  value       = var.enable_default_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow[0].name : null
}

output "alert_email" {
  description = "Email address subscribed to security + cost alerts (echoed back for confirmation)."
  value       = var.alert_email
  sensitive   = false
}
