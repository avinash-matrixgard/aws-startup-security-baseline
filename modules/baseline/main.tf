# =============================================================================
# aws-startup-security-baseline -- main module
#
# 12 controls, 22 resources. Each section is self-contained so you can read
# / fork / adapt one control at a time. Controls are numbered to match the
# README's table.
#
# Maintained by MatrixGard <https://matrixgard.com>
# License: MIT
# =============================================================================

# -----------------------------------------------------------------------------
# Common data sources + locals
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # All resources tagged with these on top of var.tags
  module_tags = merge(
    var.tags,
    {
      Module = "aws-startup-security-baseline"
      Source = "github.com/avinash-matrixgard/aws-startup-security-baseline"
    }
  )

  trail_name      = var.trail_name != "" ? var.trail_name : "${var.name_prefix}-trail"
  trail_bucket    = "${var.name_prefix}-cloudtrail-${local.account_id}-${local.region}"
  config_bucket   = "${var.name_prefix}-config-${local.account_id}-${local.region}"
  sns_topic_name  = "${var.name_prefix}-alerts"
  flow_log_group  = "/aws/vpc/${var.name_prefix}-default-flow-logs"
  config_role     = "${var.name_prefix}-config-recorder"
  flow_log_role   = "${var.name_prefix}-flow-logs"
}

# -----------------------------------------------------------------------------
# SNS topic for ALL alerts (security + cost) -- consumed by alarms below
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name              = local.sns_topic_name
  display_name      = "MatrixGard Security + Cost Alerts"
  kms_master_key_id = "alias/aws/sns" # AWS-managed key, free
  tags              = local.module_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Topic policy lets AWS Budgets + CloudWatch Events publish to this topic
data "aws_iam_policy_document" "alerts_topic_policy" {
  statement {
    sid    = "AllowBudgetsPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic_policy.json
}

# =============================================================================
# CONTROL 1 -- IAM password policy
# =============================================================================

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.password_min_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = var.password_max_age_days == 0 ? null : var.password_max_age_days
  password_reuse_prevention      = var.password_reuse_prevention == 0 ? null : var.password_reuse_prevention
  hard_expiry                    = false
}

# =============================================================================
# CONTROL 4 -- S3 account-level public access block
# Single account-wide knob that prevents *any* future S3 bucket from
# accidentally going public. Bucket-level settings remain in effect.
# =============================================================================

resource "aws_s3_account_public_access_block" "this" {
  account_id              = local.account_id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# CONTROL 8 -- Default EBS encryption
# Every NEW EBS volume created in this region is encrypted at rest by default
# using the AWS-managed KMS key. Existing volumes are NOT retroactively
# encrypted (you'd need snapshot+restore for those).
# =============================================================================

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# =============================================================================
# CONTROL 3 -- CloudTrail (multi-region, KMS-encrypted, log file validation)
# =============================================================================

# KMS key used to encrypt CloudTrail logs at rest (in S3) and SNS notifications
resource "aws_kms_key" "cloudtrail" {
  count                   = var.create_cloudtrail ? 1 : 0
  description             = "Key used to encrypt CloudTrail logs for ${local.trail_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.cloudtrail_kms[0].json
  tags                    = local.module_tags
}

resource "aws_kms_alias" "cloudtrail" {
  count         = var.create_cloudtrail ? 1 : 0
  name          = "alias/${var.name_prefix}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].key_id
}

data "aws_iam_policy_document" "cloudtrail_kms" {
  count = var.create_cloudtrail ? 1 : 0

  # Account root must retain full key admin to avoid lockout
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # CloudTrail must be able to use the key to encrypt log objects
  statement {
    sid    = "AllowCloudTrailEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  # Decrypt access for principals reading the trail (e.g., Athena queries)
  statement {
    sid    = "AllowCloudTrailDecryption"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:Decrypt", "kms:ReEncryptFrom"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket" "trail" {
  count         = var.create_cloudtrail ? 1 : 0
  bucket        = local.trail_bucket
  force_destroy = false # never let terraform delete logs in error
  tags          = local.module_tags
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count                   = var.create_cloudtrail ? 1 : 0
  bucket                  = aws_s3_bucket.trail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail" {
  count  = var.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count  = var.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count  = var.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "tier-and-expire"
    status = "Enabled"

    filter {} # apply to all objects in the bucket

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.cloudtrail_log_retention_days > 0 ? [1] : []
      content {
        days = var.cloudtrail_log_retention_days
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 7 # versioning is on; clean prior versions quickly
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  count = var.create_cloudtrail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"]
    }
  }

  # Deny any non-TLS access (Security Hub control S3.5)
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail[0].arn, "${aws_s3_bucket.trail[0].arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count  = var.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket[0].json
}

resource "aws_cloudtrail" "this" {
  count                         = var.create_cloudtrail ? 1 : 0
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail[0].id
  is_multi_region_trail         = true
  is_organization_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail[0].arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_cloudwatch[0].arn
  enable_logging                = true
  tags                          = local.module_tags

  depends_on = [aws_s3_bucket_policy.trail]
}

# CloudWatch log group for CloudTrail -- enables metric filter alarms below
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count             = var.create_cloudtrail ? 1 : 0
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudtrail[0].arn
  tags              = local.module_tags
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  count = var.create_cloudtrail ? 1 : 0
  name  = "${var.name_prefix}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.module_tags
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  count = var.create_cloudtrail ? 1 : 0
  name  = "${var.name_prefix}-cloudtrail-cw-policy"
  role  = aws_iam_role.cloudtrail_to_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
    }]
  })
}

# =============================================================================
# CONTROL 5 -- GuardDuty
# =============================================================================

resource "aws_guardduty_detector" "this" {
  count                        = var.enable_guardduty ? 1 : 0
  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency
  tags                         = local.module_tags
}

# Send GuardDuty HIGH+CRITICAL findings to SNS via EventBridge
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.name_prefix}-guardduty-high-findings"
  description = "Forward GuardDuty HIGH and CRITICAL severity findings to SNS"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ "numeric" : [">=", 7] }] # 7.0+ = HIGH, 8.9+ = CRITICAL
    }
  })
  tags = local.module_tags
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}

# =============================================================================
# CONTROL 6 -- Security Hub + AFSBP standard
# =============================================================================

resource "aws_securityhub_account" "this" {
  count                    = var.enable_security_hub ? 1 : 0
  enable_default_standards = false # we explicitly subscribe below
}

resource "aws_securityhub_standards_subscription" "afsbp" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# =============================================================================
# CONTROL 7 -- IAM Access Analyzer (account scope)
# =============================================================================

resource "aws_accessanalyzer_analyzer" "this" {
  analyzer_name = "${var.name_prefix}-access-analyzer"
  type          = "ACCOUNT"
  tags          = local.module_tags
}

# =============================================================================
# CONTROL 9 -- VPC Flow Logs on default VPC
# =============================================================================

data "aws_vpc" "default" {
  count   = var.enable_default_vpc_flow_logs ? 1 : 0
  default = true
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  count             = var.enable_default_vpc_flow_logs ? 1 : 0
  name              = local.flow_log_group
  retention_in_days = var.flow_log_retention_days
  tags              = local.module_tags
}

resource "aws_iam_role" "vpc_flow" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0
  name  = local.flow_log_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.module_tags
}

resource "aws_iam_role_policy" "vpc_flow" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0
  name  = "${local.flow_log_role}-policy"
  role  = aws_iam_role.vpc_flow[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "default" {
  count                = var.enable_default_vpc_flow_logs ? 1 : 0
  vpc_id               = data.aws_vpc.default[0].id
  iam_role_arn         = aws_iam_role.vpc_flow[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "REJECT" # only log dropped traffic by default; cheaper, more useful
  tags                 = local.module_tags
}

# =============================================================================
# CONTROL 10 -- AWS Config recorder (high-blast-radius types only by default)
# =============================================================================

resource "aws_iam_role" "config" {
  count = var.enable_config_recorder ? 1 : 0
  name  = local.config_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.module_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_config_recorder ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_s3_bucket" "config" {
  count         = var.enable_config_recorder ? 1 : 0
  bucket        = local.config_bucket
  force_destroy = false
  tags          = local.module_tags
}

resource "aws_s3_bucket_public_access_block" "config" {
  count                   = var.enable_config_recorder ? 1 : 0
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config" {
  count  = var.enable_config_recorder ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "config_bucket" {
  count = var.enable_config_recorder ? 1 : 0

  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config[0].arn]
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config[0].arn}/AWSLogs/${local.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config[0].arn, "${aws_s3_bucket.config[0].arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count  = var.enable_config_recorder ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  policy = data.aws_iam_policy_document.config_bucket[0].json
}

resource "aws_config_configuration_recorder" "this" {
  count    = var.enable_config_recorder ? 1 : 0
  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = var.config_record_all
    include_global_resource_types = var.config_record_all # IAM is global; skip if scoped

    dynamic "recording_mode" {
      for_each = var.config_record_all ? [] : [1]
      content {
        recording_frequency = "CONTINUOUS"
      }
    }

    resource_types = var.config_record_all ? [] : var.config_recorded_resource_types
  }
}

resource "aws_config_delivery_channel" "this" {
  count          = var.enable_config_recorder ? 1 : 0
  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config[0].id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  count      = var.enable_config_recorder ? 1 : 0
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# =============================================================================
# CONTROL 11 -- Cost Anomaly Detection
# =============================================================================

resource "aws_ce_anomaly_monitor" "all_services" {
  count             = var.enable_cost_anomaly_detection ? 1 : 0
  name              = "${var.name_prefix}-cost-anomaly"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags              = local.module_tags
}

resource "aws_ce_anomaly_subscription" "alerts" {
  count            = var.enable_cost_anomaly_detection ? 1 : 0
  name             = "${var.name_prefix}-cost-anomaly-sub"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.all_services[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.cost_anomaly_threshold_usd)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = local.module_tags
}

# =============================================================================
# CONTROL 12 -- AWS Budgets monthly cap with threshold alerts
# =============================================================================

resource "aws_budgets_budget" "monthly_cap" {
  name              = "${var.name_prefix}-monthly-cap"
  budget_type       = "COST"
  limit_amount      = tostring(var.monthly_budget_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  dynamic "notification" {
    for_each = var.budget_alert_thresholds_pct
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
      subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
    }
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# =============================================================================
# CONTROL 2 -- Root account usage + missing-MFA alarms via CloudTrail logs
# Requires Control 3 (CloudTrail with CloudWatch Logs integration). If you
# disable CloudTrail (var.create_cloudtrail = false), these alarms are skipped.
# =============================================================================

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  count          = var.create_cloudtrail ? 1 : 0
  name           = "${var.name_prefix}-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsageCount"
    namespace = "MatrixGard/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  count               = var.create_cloudtrail ? 1 : 0
  alarm_name          = "${var.name_prefix}-root-account-usage-detected"
  alarm_description   = "Root account was used. Investigate immediately -- root should be MFA-locked and not used for any operational task."
  namespace           = "MatrixGard/Security"
  metric_name         = "RootAccountUsageCount"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  period              = 300
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.module_tags
}

# Alarm if console login by IAM user happens without MFA (a strong signal of credential compromise)
resource "aws_cloudwatch_log_metric_filter" "console_no_mfa" {
  count          = var.create_cloudtrail ? 1 : 0
  name           = "${var.name_prefix}-console-login-no-mfa"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"

  metric_transformation {
    name      = "ConsoleLoginWithoutMFA"
    namespace = "MatrixGard/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "console_no_mfa" {
  count               = var.create_cloudtrail ? 1 : 0
  alarm_name          = "${var.name_prefix}-console-login-without-mfa"
  alarm_description   = "An IAM user logged into the AWS console without MFA. Force-enable MFA on the user, rotate their password, audit recent activity."
  namespace           = "MatrixGard/Security"
  metric_name         = "ConsoleLoginWithoutMFA"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  period              = 300
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.module_tags
}

# Alarm if anyone tries to delete CloudTrail logs from the trail S3 bucket
resource "aws_cloudwatch_log_metric_filter" "trail_log_tamper" {
  count          = var.create_cloudtrail ? 1 : 0
  name           = "${var.name_prefix}-cloudtrail-tampering"
  log_group_name = aws_cloudwatch_log_group.cloudtrail[0].name
  pattern        = "{ ($.eventSource = \"cloudtrail.amazonaws.com\") && (($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\")) }"

  metric_transformation {
    name      = "CloudTrailTamperingAttempts"
    namespace = "MatrixGard/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "trail_log_tamper" {
  count               = var.create_cloudtrail ? 1 : 0
  alarm_name          = "${var.name_prefix}-cloudtrail-tampering-detected"
  alarm_description   = "Someone tried to disable, delete, or modify the CloudTrail trail. This is a strong indicator of an attacker covering tracks."
  namespace           = "MatrixGard/Security"
  metric_name         = "CloudTrailTamperingAttempts"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  period              = 300
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.module_tags
}
