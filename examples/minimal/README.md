# `examples/minimal` -- greenfield deployment

The simplest way to apply the full baseline to an AWS account that has no pre-existing CloudTrail / GuardDuty / Security Hub configuration.

## Prerequisites

- Terraform >= 1.6.0
- AWS credentials in your shell (env vars, `~/.aws/credentials` profile, or AWS SSO session)
- IAM principal with broad create perms across IAM, KMS, S3, CloudTrail, GuardDuty, Security Hub, Access Analyzer, EBS, VPC, Config, Cost Explorer, Budgets, SNS, and CloudWatch. Easiest: assume a `terraform-apply` role with `AdministratorAccess` for the bootstrap.

## Apply

```bash
# 1. Drop into this directory
cd examples/minimal

# 2. Set your inputs (or use TF_VAR_ env vars)
cat > terraform.tfvars <<EOF
aws_region         = "us-east-1"
alert_email        = "security@yourstartup.com"
monthly_budget_usd = 1000
EOF

# 3. Plan + apply
terraform init
terraform plan -out=baseline.tfplan
terraform apply baseline.tfplan

# 4. Confirm SNS subscription
#    AWS will email a confirmation link to your alert_email.
#    Click it. Without confirmation, you receive ZERO alerts.
```

Expected `terraform apply` time: 3-5 minutes.

## After applying

1. **Confirm SNS subscription** — check the inbox of `var.alert_email` for an email from `no-reply@sns.amazonaws.com` and click the confirmation link.
2. **Verify in console:**
   - GuardDuty → Detectors → confirm enabled
   - Security Hub → Standards → confirm "AWS Foundational Security Best Practices" subscribed
   - CloudTrail → Trails → confirm `security-baseline-trail` is logging
   - Access Analyzer → confirm one analyzer at account scope
   - Config → confirm recorder is recording
   - Budgets → confirm `security-baseline-monthly-cap` exists
3. **Wait 6-24 hours** for Security Hub to populate findings, then review.

## Removing the baseline

```bash
terraform destroy
```

Note: the CloudTrail S3 bucket and the Config S3 bucket have `force_destroy = false` to prevent accidental log deletion. To fully tear down, you must empty those buckets manually first OR temporarily set `force_destroy = true` on the relevant `aws_s3_bucket` resources in `modules/baseline/main.tf`.

## Customization

Need to change defaults (password policy, retention, GuardDuty frequency, etc.)? See [`modules/baseline/README.md`](../../modules/baseline/README.md) for every input the module accepts.
