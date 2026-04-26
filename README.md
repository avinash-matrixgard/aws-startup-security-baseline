# aws-startup-security-baseline

> **The 12 AWS security controls every 5-engineer seed startup should turn on this afternoon — and the 80 CIS controls you can skip until Series A.**

A small, opinionated Terraform module. One `terraform apply` lands the controls that account for the vast majority of real-world AWS startup breaches. Each control documented with **why it matters**, **what breaks if you skip it**, and **when you'd safely turn it off**.

Maintained by [MatrixGard](https://matrixgard.com) — fractional DevSecOps for pre-seed and seed startups across India, Singapore, UAE, UK, and US.

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6-blueviolet)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS_Provider-%3E%3D5.40-orange)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Why this exists

Every CIS Benchmark, Well-Architected pillar, and "AWS security baseline" Terraform module on GitHub has the same problem for a 5-person seed startup: **it's overwhelming, half of it doesn't apply yet, and you'll never finish reading the README, let alone applying it.**

So you do nothing. And the next time someone audits the account, you have a leaked S3 bucket, no MFA on root, no log trail of who did what, and a $40,000 GPU instance some intern launched in `us-east-1` two months ago that nobody noticed.

This module fixes the smallest set of things that prevent the largest share of real incidents we've seen across audits of pre-seed and seed startups. **No more, no less.** When you're 50 engineers with a SOC 2 deadline you'll outgrow it; that's fine. The point is to not have a security backlog larger than your engineering org while you're still figuring out product-market fit.

---

## What's in (the 12 controls)

| # | Control                                         | What it actually does                                                       | Cost      |
|---|-------------------------------------------------|------------------------------------------------------------------------------|-----------|
| 1 | IAM password policy                             | Forces strong passwords, rotation, no reuse                                  | $0        |
| 2 | Root MFA enforcement check                      | CloudWatch alarm if root account is used or root MFA is missing              | ~$0.10/mo |
| 3 | CloudTrail (multi-region, log validation, KMS)  | Tamper-evident audit log of every API call across every region               | ~$2/mo    |
| 4 | S3 account-level public access block            | Kills the entire "accidentally public S3 bucket" class of breach in one knob | $0        |
| 5 | GuardDuty                                       | Threat detection on CloudTrail + DNS + VPC Flow Logs                         | Pay-per-scan, ~$3-30/mo at startup scale |
| 6 | Security Hub + AWS Foundational Best Practices  | Single dashboard for security findings across your account                   | ~$0.0010/check, ~$5/mo at startup scale |
| 7 | IAM Access Analyzer                             | Flags any resource policy granting access outside your account               | $0        |
| 8 | Default EBS encryption                          | Every new EBS volume is encrypted at rest, no exceptions                     | $0        |
| 9 | Default VPC Flow Logs                           | Network audit trail for the VPC your team accidentally launches things in    | ~$0.50/mo |
| 10| AWS Config recorder (high-blast-radius types)   | Change history for IAM, S3 buckets, security groups — what changed, when, by whom | ~$2/mo |
| 11| AWS Cost Anomaly Detection                      | Email when AWS spend spikes outside your normal pattern                      | $0        |
| 12| AWS Budgets ($N/month threshold alerts)         | Email at 80% and 100% of your declared monthly cap                           | $0        |

**Total monthly cost at startup scale: ~$10-40/month.** Less than one engineer's lunch.

---

## What's deliberately out (the skip list)

Other modules add 50+ controls and call themselves "comprehensive." This one calls those out as **premature for seed-stage** and tells you exactly when to revisit:

| Control                          | Why we skip it (for now)                                                              | When to add it                                       |
|----------------------------------|----------------------------------------------------------------------------------------|------------------------------------------------------|
| **AWS WAF**                      | You don't have public APIs at scale yet. WAF rules without traffic = false sense of safety + $5+/mo. | First public API serving > 100k req/day              |
| **AWS Shield Advanced**          | $3,000/month minimum. Shield Standard (free) is on by default and enough for now.      | Only when contractually required, or post-DDoS       |
| **AWS Macie**                    | Data classification. Expensive ($5/GB scanned) and unnecessary until you have real PII at volume. | When you store >100GB of customer data with PII      |
| **AWS Detective**                | Incident investigation tooling. $$. Only useful AFTER an incident happens.             | After your first real incident                       |
| **AWS Audit Manager**            | Compliance framework automation. Premature optimization for SOC 2 you're not pursuing yet. | When you've signed an enterprise customer that requires SOC 2 / ISO 27001 |
| **Full CIS Benchmark (~140 controls)** | 80% of CIS controls assume an organization with multiple AWS accounts, an org-wide CloudTrail, IAM Identity Center, etc. You don't have those yet. | When you cross 25 engineers + multi-account setup    |
| **AWS Inspector**                | Vulnerability scanning for EC2 + ECR. Useful, but you should run [Trivy](https://github.com/aquasecurity/trivy) in CI first — that catches issues before they ship, not after. | When you have >10 EC2 instances or >5 ECR repos      |
| **AWS Network Firewall**         | $400/month minimum + complexity. VPC Security Groups + NACLs are sufficient at startup scale. | At Series B+ when you have a network security engineer to own it |

We'll add more skip-with-reasoning entries as the controls universe grows. **PRs welcome with reasoned additions.**

---

## Quick start (5 minutes)

```bash
# 1. Clone or download this module's source
git clone https://github.com/avinash-matrixgard/aws-startup-security-baseline.git
cd aws-startup-security-baseline/examples/minimal

# 2. Edit terraform.tfvars (or use TF_VAR_ env vars)
cat > terraform.tfvars <<EOF
alert_email          = "security@yourstartup.com"
monthly_budget_usd   = 1000
trail_name           = "yourstartup-trail"
EOF

# 3. Plan + apply
terraform init
terraform plan -out=baseline.tfplan
terraform apply baseline.tfplan
```

That's it. ~3 minutes of `terraform apply` time later, your account has all 12 controls live.

---

## Module usage

```hcl
module "security_baseline" {
  source = "github.com/avinash-matrixgard/aws-startup-security-baseline//modules/baseline?ref=v0.1.0"

  # required
  alert_email        = "security@yourstartup.com"
  monthly_budget_usd = 1000

  # optional with sensible defaults
  trail_name                  = "startup-trail"            # default: "security-baseline-trail"
  password_min_length         = 14                         # default: 14
  password_max_age_days       = 90                         # default: 90
  guardduty_finding_frequency = "FIFTEEN_MINUTES"          # default: "FIFTEEN_MINUTES"
  enable_security_hub         = true                       # default: true
  enable_config_recorder      = true                       # default: true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Owner       = "platform-team"
  }
}
```

See [`modules/baseline/README.md`](modules/baseline/README.md) for the full input/output reference.

---

## What you get after `terraform apply`

A fresh `terraform apply` creates:

- 1 `aws_iam_account_password_policy`
- 1 `aws_cloudtrail` (multi-region, log file validation, KMS-encrypted)
- 1 `aws_s3_bucket` for CloudTrail logs (private, lifecycle-managed)
- 1 `aws_kms_key` for CloudTrail log encryption
- 1 `aws_s3_account_public_access_block`
- 1 `aws_guardduty_detector`
- 1 `aws_securityhub_account` + 1 `aws_securityhub_standards_subscription` (AFSBP)
- 1 `aws_accessanalyzer_analyzer` (account scope)
- 1 `aws_ebs_encryption_by_default`
- 1 `aws_flow_log` for the default VPC
- 1 `aws_config_configuration_recorder` + delivery channel + 1 `aws_config_recorder_status`
- 1 `aws_ce_anomaly_monitor` + 1 `aws_ce_anomaly_subscription`
- 1 `aws_budgets_budget` (cost-monthly, with 80% + 100% thresholds → SNS topic)
- 1 `aws_sns_topic` for security + cost alerts → subscribed to your `alert_email`
- 4 `aws_cloudwatch_metric_alarm` resources (root usage, root MFA, CloudTrail S3 deletes, GuardDuty critical findings)

Total: ~22 AWS resources, all tagged with whatever you pass to `var.tags`.

---

## Production caveats (read these before applying)

1. **Email confirmation required.** AWS SNS sends a confirmation email to `var.alert_email` after the first apply. **You must click the confirmation link** or you won't receive any alerts. Check spam.
2. **AWS Config recorder costs.** Config charges per configuration item recorded. We restrict the recorder to high-blast-radius resource types (IAM, S3, security groups, NACLs) by default — this keeps costs at ~$2/month for a typical seed startup. If you set `var.config_record_all = true`, expect $10-30/month.
3. **CloudTrail S3 bucket lifecycle.** Default lifecycle moves logs to S3 IA after 30 days, Glacier after 90, deletes after 365. Override via `var.cloudtrail_log_retention_days` if you need longer retention for compliance.
4. **GuardDuty in `us-east-1` only by default.** Multi-region GuardDuty multiplies cost ~5x. We only enable it in your primary region. Override `var.guardduty_regions = ["us-east-1", "ap-south-1"]` if you operate in multiple regions.
5. **Security Hub auto-enables 4-5 standards by default if you do nothing.** This module enables ONLY AWS Foundational Best Practices to keep finding noise low. CIS / PCI / NIST standards remain off — turn them on yourself when you actually need them.
6. **Don't run this on an account that already has CloudTrail / GuardDuty / Security Hub configured.** Use [`examples/with-existing-cloudtrail/`](examples/with-existing-cloudtrail/) for the brownfield case.
7. **Run from a CI/CD pipeline with a dedicated `terraform-apply` IAM role**, not from a developer laptop. The module needs significant IAM perms — see [`docs/required-iam-perms.md`](docs/required-iam-perms.md) for the minimum policy.

---

## Tested against

| Component         | Versions tested                       |
|-------------------|---------------------------------------|
| Terraform         | 1.6.x, 1.7.x, 1.8.x, 1.9.x            |
| AWS Provider      | 5.40+, 5.50+, 5.60+, 5.70+, 5.80+     |
| AWS Regions       | us-east-1, us-west-2, eu-west-1, ap-south-1, ap-southeast-1 |
| AWS Account types | Single-account (root org or standalone) |

We do **not** test against AWS Organizations / multi-account SCPs / Control Tower — those are post-seed-stage concerns. PRs welcome from teams running this in those contexts.

---

## When to outgrow this module

You should retire `aws-startup-security-baseline` and graduate to a real platform team's setup when **any two of these are true**:

- You've crossed 25 engineers
- You operate in 2+ AWS accounts (prod / staging / dev separation)
- You've signed an enterprise customer that requires SOC 2 Type II or ISO 27001
- You have a dedicated security engineer (or are hiring for one)
- You process regulated data (HIPAA / PCI-DSS / RBI / GDPR sensitive categories)

At that point: keep the controls themselves, migrate them into your org-wide IaC structure (likely Terragrunt or Terraform Cloud workspaces), add multi-account CloudTrail aggregation via AWS Organizations, layer in IAM Identity Center, and reference [AWS Control Tower](https://aws.amazon.com/controltower/) as your new baseline.

---

## What this module does NOT do

Some things this module deliberately doesn't touch:

- Application-layer security (your code, your dependencies, your container images) — use [Trivy](https://github.com/aquasecurity/trivy), [Snyk](https://snyk.io), [OWASP ZAP](https://www.zaproxy.org/) in CI
- Secret rotation (AWS Secrets Manager / HashiCorp Vault setup) — out of scope
- Data classification / DLP — Macie territory, premature
- Network microsegmentation (Service Mesh, Network Firewall) — premature
- Per-workload IAM roles — that's your application architecture, not a baseline
- Compliance attestation (SOC 2, ISO 27001 evidence collection) — different problem space
- Anything about GCP, Azure, Kubernetes, or non-AWS

For most of those, MatrixGard's [services](https://matrixgard.com/services) cover them as part of a fractional engagement. This OSS module is the day-1 baseline; the engagement is the rest.

---

## Real-world results

This baseline is what we apply on day 1 of every MatrixGard cloud security engagement. From the public [saysri.ai case study](https://matrixgard.com/case-studies/saysri-audit/):

> Before: TLS 1.0 enabled, public blob storage, no WAF, orphaned cloud resources bleeding money quietly.
>
> After: 8 critical security vulnerabilities fixed, 70% of orphaned cloud resources eliminated, production-grade security posture achieved — in 7 working days.

Want a similar audit on your AWS, GCP, or Azure account? [Book a free 20-minute infrastructure review](https://matrixgard.com/book) — we'll tell you what's exposed, what's wasted, and what needs fixing. No pitch.

---

## FAQ

**Q: I already use AWS Organizations / Control Tower / Identity Center. Should I still use this?**
A: No. Those tools are designed for multi-account orgs and supersede most of what this module does. This is for single-account startups who haven't justified that complexity yet.

**Q: Will this work with my existing CloudTrail?**
A: Use [`examples/with-existing-cloudtrail/`](examples/with-existing-cloudtrail/) — it shows how to skip our trail creation and reference yours.

**Q: Does this set up cross-account access for our auditor?**
A: No. That's a separate concern.

**Q: Why no Terraform Cloud / Spacelift / Atlantis examples?**
A: This module works fine in those tools — examples are just `module "security_baseline" { source = "..." }` blocks. We'd rather keep examples to the simplest possible local-state case so the module itself is easy to evaluate.

**Q: Why not publish to the Terraform Registry?**
A: Coming. We want a few real-world deployments to validate first. PR / issue if you'd like to be one.

**Q: I want to contribute. What's the bar?**
A: See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: every new control needs a "why we add it" + "what breaks if you skip it" + "when to graduate off it" entry, same format as the existing 12. PRs that add controls without the reasoning will be asked to add it.

**Q: Why MIT and not Apache 2.0?**
A: Patent grant rarely matters for IaC modules at this scope, MIT is shorter, and most adopters will inline the controls anyway. If your legal team requires Apache 2.0, fork it.

---

## Documentation

- [`modules/baseline/README.md`](modules/baseline/README.md) — module-level inputs / outputs reference
- [`docs/controls.md`](docs/controls.md) — every control documented with rationale + AWS doc links
- [`CHANGELOG.md`](CHANGELOG.md) — version history

(Runbooks for incident response on individual control alarms are coming in v0.2.)

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it. No warranty, no liability — read the actual license.

## Maintained by

[MatrixGard](https://matrixgard.com) — fractional cloud, infrastructure, and security team for pre-seed and seed startups. We become your DevSecOps team on a monthly retainer for a fraction of the cost of a senior hire. Operating across India, Singapore, UAE, UK, and US.

Issues, PRs, and questions: file in this repo or email avinash@matrixgard.com.
