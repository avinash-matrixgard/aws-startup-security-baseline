# `examples/with-existing-cloudtrail` -- brownfield deployment

Use this example when the AWS account already has a multi-region CloudTrail trail (e.g., set up by AWS Control Tower, your auditor, or a prior IaC stack).

## What changes vs `examples/minimal`

A single input flip: `create_cloudtrail = false`. That skips:

- `aws_cloudtrail` (we use your existing trail)
- `aws_s3_bucket` for trail logs
- `aws_kms_key` for trail encryption
- `aws_cloudwatch_log_group` for the trail
- The 3 CloudTrail-metric-filter alarms (root usage, console-without-MFA, trail tampering)
- The IAM role + policy that ferries trail events to CloudWatch Logs

Everything else (GuardDuty, Security Hub, Access Analyzer, Config recorder, password policy, S3 account public access block, EBS encryption, VPC Flow Logs, Cost Anomaly Detection, Budgets, SNS topic + email subscription) is created exactly as in the minimal example.

## When you want both: existing trail AND the alarms

The 3 CloudTrail-derived alarms are valuable. To keep them while using your existing trail:

1. Confirm your existing CloudTrail has a CloudWatch Logs delivery target. If not, add one in your trail's IaC.
2. Apply this example to get the SNS topic + everything else.
3. Add `aws_cloudwatch_log_metric_filter` and `aws_cloudwatch_metric_alarm` resources in your own IaC pointing at your trail's log group, with `alarm_actions = [module.security_baseline.sns_topic_arn]`.

The 3 metric filters this module uses (for reference):

- **Root account usage:** `{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }`
- **Console login without MFA:** `{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ($.userIdentity.type = "IAMUser") && ($.responseElements.ConsoleLogin = "Success") }`
- **CloudTrail tampering:** `{ ($.eventSource = "cloudtrail.amazonaws.com") && (($.eventName = "StopLogging") || ($.eventName = "DeleteTrail") || ($.eventName = "UpdateTrail")) }`

## Apply

```bash
cd examples/with-existing-cloudtrail

cat > terraform.tfvars <<EOF
aws_region         = "us-east-1"
alert_email        = "security@yourstartup.com"
monthly_budget_usd = 1000
EOF

terraform init
terraform plan -out=baseline.tfplan
terraform apply baseline.tfplan
```
