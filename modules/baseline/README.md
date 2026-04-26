# `modules/baseline` -- input + output reference

This is the source-of-truth module. The top-level repo README explains the **why** of every control. This file is the **interface reference** for module callers.

## Source

```hcl
module "security_baseline" {
  source = "github.com/avinash-matrixgard/aws-startup-security-baseline//modules/baseline?ref=v0.1.0"
  # ... see Inputs below
}
```

## Inputs

### Required

| Name                  | Type     | Description                                                                                                |
|-----------------------|----------|------------------------------------------------------------------------------------------------------------|
| `alert_email`         | `string` | Email address for security + cost alerts. Must confirm SNS subscription via emailed link before alerts fire.|
| `monthly_budget_usd`  | `number` | Monthly AWS spend cap in USD. Alerts at 80% (warning) and 100% (critical).                                 |

### Naming + tagging

| Name          | Type          | Default              | Description                                                                                |
|---------------|---------------|----------------------|--------------------------------------------------------------------------------------------|
| `name_prefix` | `string`      | `"security-baseline"`| Prefix prepended to all created resource names. Lowercase, hyphens allowed.                |
| `tags`        | `map(string)` | `{}`                 | Tags applied to every resource. Module always adds `Module` and `Source` on top.           |

### IAM password policy (Control 1)

| Name                          | Type     | Default | Description                                                              |
|-------------------------------|----------|---------|--------------------------------------------------------------------------|
| `password_min_length`         | `number` | `14`    | Minimum password length. Must be 8-128.                                  |
| `password_max_age_days`       | `number` | `365`   | Max age before forced rotation. 0 = no rotation. Must be 0-1095.         |
| `password_reuse_prevention`   | `number` | `24`    | Number of previous passwords prevented from reuse. Must be 0-24.         |

### CloudTrail (Control 3)

| Name                            | Type     | Default                | Description                                                                                                       |
|---------------------------------|----------|------------------------|-------------------------------------------------------------------------------------------------------------------|
| `create_cloudtrail`             | `bool`   | `true`                 | Create a multi-region CloudTrail. Set false if you already have one (use `with-existing-cloudtrail` example).     |
| `trail_name`                    | `string` | `""`                   | Trail name. Default: `{name_prefix}-trail`.                                                                       |
| `cloudtrail_log_retention_days` | `number` | `365`                  | Days to keep logs in S3 before deletion. 0 = forever.                                                             |

### GuardDuty (Control 5)

| Name                          | Type     | Default            | Description                                                                                |
|-------------------------------|----------|--------------------|--------------------------------------------------------------------------------------------|
| `enable_guardduty`            | `bool`   | `true`             | Enable GuardDuty in the current region.                                                    |
| `guardduty_finding_frequency` | `string` | `"FIFTEEN_MINUTES"`| Publication cadence to CloudWatch Events. One of FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS.     |

### Security Hub (Control 6)

| Name                  | Type   | Default | Description                                                                              |
|-----------------------|--------|---------|------------------------------------------------------------------------------------------|
| `enable_security_hub` | `bool` | `true`  | Enable Security Hub + AWS Foundational Best Practices subscription. CIS / PCI / NIST stay off. |

### AWS Config (Control 10)

| Name                              | Type           | Default                              | Description                                                                                  |
|-----------------------------------|----------------|--------------------------------------|----------------------------------------------------------------------------------------------|
| `enable_config_recorder`          | `bool`         | `true`                               | Enable AWS Config recorder.                                                                  |
| `config_record_all`               | `bool`         | `false`                              | If true, record every supported resource type (~$10-30/mo). If false, restricted set (~$2/mo). |
| `config_recorded_resource_types`  | `list(string)` | `[IAM, S3, EC2/SecurityGroup, ...]`  | Recorded types when `config_record_all = false`.                                              |

### VPC Flow Logs (Control 9)

| Name                            | Type     | Default | Description                                                                              |
|---------------------------------|----------|---------|------------------------------------------------------------------------------------------|
| `enable_default_vpc_flow_logs`  | `bool`   | `true`  | Enable VPC Flow Logs on the default VPC.                                                 |
| `flow_log_retention_days`       | `number` | `90`    | CloudWatch Logs retention. Must be a valid CW retention value.                           |

### Cost monitoring (Controls 11 + 12)

| Name                            | Type           | Default      | Description                                                                                  |
|---------------------------------|----------------|--------------|----------------------------------------------------------------------------------------------|
| `enable_cost_anomaly_detection` | `bool`         | `true`       | Create a Cost Anomaly Detection monitor + email subscription.                                |
| `cost_anomaly_threshold_usd`    | `number`       | `100`        | Min USD impact for an anomaly to trigger.                                                    |
| `budget_alert_thresholds_pct`   | `list(number)` | `[80, 100]`  | Percentage thresholds at which AWS Budgets sends alerts.                                     |

## Outputs

| Name                       | Description                                                                            |
|----------------------------|----------------------------------------------------------------------------------------|
| `sns_topic_arn`            | ARN of the alerts SNS topic. Subscribe Slack/PagerDuty here when you outgrow email.    |
| `cloudtrail_arn`           | Trail ARN (null if `create_cloudtrail = false`).                                       |
| `cloudtrail_log_group_name`| CloudWatch Log Group mirroring the trail.                                              |
| `cloudtrail_s3_bucket`     | S3 bucket holding trail log files.                                                     |
| `cloudtrail_kms_key_arn`   | KMS key encrypting the trail.                                                          |
| `guardduty_detector_id`    | GuardDuty detector ID.                                                                 |
| `security_hub_enabled`     | Whether Security Hub is on.                                                            |
| `access_analyzer_arn`      | IAM Access Analyzer ARN.                                                               |
| `config_recorder_name`     | Config recorder name.                                                                  |
| `config_s3_bucket`         | Bucket holding Config snapshots.                                                       |
| `monthly_budget_name`      | Budgets resource name.                                                                 |
| `vpc_flow_log_group_name`  | Default-VPC flow log group name.                                                       |
| `alert_email`              | Echo of the configured alert email.                                                    |

## Provider requirements

| Provider | Version constraint    |
|----------|-----------------------|
| `aws`    | `>= 5.40.0, < 6.0.0`  |

Terraform CLI: `>= 1.6.0`.

## Resources created

See the top-level repo README's "What you get after `terraform apply`" table — ~22 resources across IAM, KMS, S3, CloudTrail, GuardDuty, Security Hub, Access Analyzer, EBS, VPC, Config, Cost Explorer, Budgets, SNS, and CloudWatch.

## Required IAM permissions to apply

The IAM principal running `terraform apply` needs broad create/update perms across all the AWS services listed above. The simplest viable approach for a startup is to apply this from a CI/CD pipeline assuming a dedicated `terraform-apply` role with `AdministratorAccess` (acceptable for IaC bootstrap), or compose a least-privilege policy from the AWS service docs for each resource type.

A CIS-grade least-privilege policy generator is on the roadmap (PR welcome).
