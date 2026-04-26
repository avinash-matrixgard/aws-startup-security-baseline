# Controls reference

Per-control documentation. Each entry follows the same structure:

- **What it does** — one sentence, plain English
- **AWS resources created** — exactly which `aws_*` resources back it
- **Configuration choices** — non-obvious defaults explained
- **Why it matters** — the failure mode it prevents
- **What breaks if you skip it** — honest "you will eventually regret this because…"
- **When to graduate off it** — when an org has outgrown the control's value
- **References** — AWS docs, NIST controls, public incidents

If you're skimming, the "Why it matters" + "What breaks if you skip it" rows are the ones to read.

---

## Control 1 — IAM password policy

**What it does:** Enforces a strong password policy (length, complexity, rotation, history) for all IAM users in the account.

**AWS resources:** `aws_iam_account_password_policy`

**Configuration choices:**
- `password_min_length = 14` — NIST 800-63B's current minimum is 8, but seed-stage password reuse is rampant; 14 hardens against credential-stuffing attacks using leaked password lists.
- `password_max_age_days = 365` — NIST 800-63B no longer recommends periodic rotation (research shows it leads to weaker passwords). But PCI-DSS, ISO 27001, and RBI Master Direction still expect ≤365 day rotation. We default to 365 to satisfy compliance frameworks; set to 0 to disable rotation if your framework allows.
- `password_reuse_prevention = 24` — matches CIS AWS Benchmark 1.5.0.
- `require_lowercase + uppercase + numbers + symbols = true` — standard.
- `hard_expiry = false` — passwords expire but users can change at next login. `true` would lock users out entirely on expiry, which causes operational pain.

**Why it matters:** IAM users with weak passwords are the #1 entry point for opportunistic AWS account compromises. Credential-stuffing attacks use leaked password databases against millions of services daily; without a policy, "Password123" or your CTO's pet's name will eventually appear in a public dump and your account is compromised.

**What breaks if you skip it:** AWS root + IAM users may use any password. New IAM users default to no policy enforcement. Auditors flag CIS 1.5-1.11 controls as failed. Your first auditor email will be about this.

**When to graduate off it:** When you've migrated all human access to AWS IAM Identity Center (formerly SSO) backed by your IdP (Google Workspace, Okta, Azure AD). At that point, password policy is enforced upstream by the IdP and the AWS-side policy is moot. Typical stage: 25+ engineers, multi-account.

**References:**
- [AWS IAM password policy docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_passwords_account-policy.html)
- [NIST SP 800-63B Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- [CIS AWS Foundations Benchmark v1.5.0 controls 1.5–1.11](https://www.cisecurity.org/benchmark/amazon_web_services)

---

## Control 2 — Root account usage + MFA alarms

**What it does:** CloudWatch metric alarms that fire (and email via SNS) on three high-risk events: (a) root account is used at all, (b) any IAM user logs into the console without MFA, (c) anyone tries to disable, delete, or modify the CloudTrail trail.

**AWS resources:** `aws_cloudwatch_log_metric_filter` × 3 + `aws_cloudwatch_metric_alarm` × 3 (depend on Control 3's CloudTrail-to-CloudWatch-Logs delivery).

**Configuration choices:**
- `evaluation_periods = 1, period = 300` — alarm fires within 5 minutes of detection. Faster than most incident response SLAs.
- `treat_missing_data = "notBreaching"` — silence is treated as "no events," not as "alarm state." Avoids spurious alerts when there's no log data.
- Filters target only `userIdentity.type = "Root"` for control 2(a) — service-attributed events (`AwsServiceEvent`) are excluded so AWS-internal automation doesn't trigger false positives.

**Why it matters:** The root account has unlimited authority over your entire AWS bill, every resource, every IAM policy. Any usage of root for operational tasks is anomalous. Console login without MFA on an IAM user is the strongest signal of credential compromise, second only to API calls from unexpected geographies. CloudTrail tampering is the textbook attacker move to cover tracks — if you don't catch it, you lose the only audit trail you have.

**What breaks if you skip it:** Account compromises go undetected for weeks. The Capital One 2019 breach went undetected for ~4 months because audit-trail anomalies were not alerted on. Your post-incident forensics is "we don't know when it started."

**When to graduate off it:** Never — keep these alarms forever. They are CIS Benchmark 4.x controls and remain critical at every org size. At enterprise scale, route the SNS topic to PagerDuty / Opsgenie / your SIEM instead of email.

**References:**
- [AWS — Monitoring with CloudWatch Logs metric filters](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/MonitoringPolicyExamples.html)
- [CIS AWS Foundations Benchmark v1.5.0 control group 4.x](https://www.cisecurity.org/benchmark/amazon_web_services)
- [Capital One 2019 breach post-mortem](https://www.capitalone.com/digital/facts2019/)

---

## Control 3 — CloudTrail (multi-region, KMS-encrypted, log file validation)

**What it does:** Records every AWS API call across every region in your account to an S3 bucket, with cryptographic log file validation and KMS encryption.

**AWS resources:**
- `aws_cloudtrail` (multi-region, log file validation, global service events on)
- `aws_s3_bucket` for logs (private, versioned, lifecycle-managed)
- `aws_kms_key` for log encryption (customer-managed, rotation enabled)
- `aws_kms_alias` for the key
- `aws_s3_bucket_policy` (CloudTrail-write only, with `aws:SourceArn` condition)
- `aws_s3_bucket_lifecycle_configuration` (IA→Glacier→delete)
- `aws_s3_bucket_versioning`
- `aws_s3_bucket_server_side_encryption_configuration`
- `aws_s3_bucket_public_access_block` (bucket-level)
- `aws_cloudwatch_log_group` (log group for metric filters in Control 2)
- `aws_iam_role` + `aws_iam_role_policy` (CloudTrail-to-CloudWatch delivery)

**Configuration choices:**
- `is_multi_region_trail = true` — captures activity in regions you didn't expect to use (which is exactly where attackers spin up cryptominers).
- `enable_log_file_validation = true` — adds digest files. If an attacker tampers with logs, validation fails on read. Without this, log files are mutable.
- `kms_key_id = customer-managed key` — AWS-managed `aws/cloudtrail` key works too but customer-managed gives you the option to rotate or revoke without AWS intervention.
- KMS key has `aws:SourceArn` condition restricting use to *this* account's *this* trail — prevents the [confused deputy](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html) class of vulnerability.
- S3 bucket lifecycle: STANDARD → STANDARD_IA after 30 days → GLACIER after 90 days → delete after `cloudtrail_log_retention_days` (default 365). Cuts log storage cost ~80% vs raw S3 Standard.
- S3 bucket policy includes a `DenyInsecureTransport` block (Security Hub control S3.5).

**Why it matters:** Without CloudTrail, there is no audit trail. Period. After-the-fact forensics, compliance attestation, breach investigation, "who deleted that S3 bucket" questions — all impossible. CloudTrail is the single highest-leverage control on AWS; everything else (Security Hub, GuardDuty, Config, custom alarms) ultimately reads from it.

**What breaks if you skip it:** Compliance auditors fail you on day 1. GuardDuty has no input data. Security Hub is empty. Custom alarms (Control 2) cannot exist. Forensics requires "vendor support cases" instead of running queries.

**When to graduate off it:** Never disable CloudTrail. When you adopt AWS Organizations, replace this single-account trail with an org-wide trail in your management account. Migrate by setting `create_cloudtrail = false` here and pointing your existing org trail's CloudWatch Logs at this module's metric filters via the brownfield example.

**References:**
- [AWS — CloudTrail Best Practices](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/best-practices-security.html)
- [AWS — Validating CloudTrail Log File Integrity](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
- [CIS AWS Foundations Benchmark v1.5.0 controls 3.1–3.11](https://www.cisecurity.org/benchmark/amazon_web_services)

---

## Control 4 — S3 account-level public access block

**What it does:** A single account-wide setting that overrides any individual bucket's public-access settings. Once enabled, no bucket in the account can serve content to the public internet, regardless of bucket policy or ACL.

**AWS resources:** `aws_s3_account_public_access_block`

**Configuration choices:** All four sub-toggles set to `true`:
- `block_public_acls = true` — rejects PUT requests adding public ACLs.
- `block_public_policy = true` — rejects PUT bucket policies that grant public access.
- `ignore_public_acls = true` — silently treats existing public ACLs as private.
- `restrict_public_buckets = true` — restricts cross-account / anonymous access via bucket policies.

**Why it matters:** Accidentally-public S3 buckets are responsible for a remarkable share of data breaches over the last decade — Booz Allen Hamilton, Capital One, Verizon, Accenture, and countless smaller incidents. The account-level block is a single irrefutable kill-switch. Even if a developer adds `"Principal": "*"` to a bucket policy in a panic, AWS rejects it.

**What breaks if you skip it:** Any developer with `s3:PutBucketPolicy` can accidentally publish data publicly. Static-site-hosting buckets that legitimately need public access still work — you whitelist them via bucket-level overrides (turning off `block_public_acls` for the specific bucket only).

**Caveat:** Static website hosting workflows (e.g., publishing a marketing site directly from S3) require turning OFF `block_public_acls` and `block_public_policy` for that *one* bucket. The account-level block doesn't prevent this — it just makes you do it explicitly per-bucket. **Recommendation:** front your static sites with CloudFront + OAC instead, keep S3 fully private. CloudFront pricing is negligible at startup scale.

**When to graduate off it:** Never. The account-level block is the strongest single security control AWS offers, and it costs $0.

**References:**
- [AWS — Blocking public access to your Amazon S3 storage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [Wikipedia: List of S3 data leak incidents](https://en.wikipedia.org/wiki/Open_data_breaches)

---

## Control 5 — GuardDuty

**What it does:** Continuously analyzes CloudTrail events, VPC Flow Logs, and DNS query logs to detect threats (compromised credentials, cryptocurrency mining, unusual API calls, communication with known malicious IPs, etc.).

**AWS resources:** `aws_guardduty_detector` + `aws_cloudwatch_event_rule` (severity ≥ 7) + `aws_cloudwatch_event_target` (forwards to SNS).

**Configuration choices:**
- `finding_publishing_frequency = "FIFTEEN_MINUTES"` — fastest detection-to-alert latency.
- EventBridge filter: `severity ≥ 7` (HIGH and CRITICAL only). MEDIUM and LOW findings stay visible in the console for review but don't email-spam you.

**Why it matters:** GuardDuty catches the active-attack scenarios that signature-based rules don't: a real human attacker using stolen credentials from a usual geography, a compromised EC2 instance reaching out to a known C2 server, a Tor exit node querying your DNS for internal hostnames. ML-driven, AWS-curated threat intel.

**Pricing:** Pay-per-event scanned. Typical seed startup spend: $3-30/month. Cost scales with CloudTrail event volume + VPC Flow Log volume + DNS query volume. Free 30-day trial when first enabled.

**What breaks if you skip it:** No active-threat detection. You only learn about incidents from secondary signals (cost spikes, customer reports, leaked data appearing in monitoring). MTTD measured in weeks instead of minutes.

**When to graduate off it:** Never disable. At enterprise scale, layer in SIEM (Splunk, Datadog, Sumo Logic) consuming the same EventBridge stream and add multi-region GuardDuty. Don't replace GuardDuty — it's the cheapest threat-intel feed you'll ever buy.

**References:**
- [AWS — GuardDuty user guide](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html)
- [AWS — GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/)

---

## Control 6 — Security Hub + AWS Foundational Best Practices

**What it does:** Aggregates security findings from GuardDuty, Macie, Inspector, IAM Access Analyzer, Config Rules, and 3rd-party tools into a single dashboard. Subscribes to the AWS Foundational Security Best Practices (AFSBP) standard for continuous compliance scoring.

**AWS resources:**
- `aws_securityhub_account` (with `enable_default_standards = false`)
- `aws_securityhub_standards_subscription` (AFSBP only)

**Configuration choices:**
- `enable_default_standards = false` + explicit subscription to AFSBP only. This module deliberately does NOT enable CIS / PCI-DSS / NIST standards by default. Each adds dozens of findings that often overlap with AFSBP, generating noise. Turn on only when you actually pursue that compliance regime.
- AFSBP version: `v/1.0.0` (current AWS standard at time of writing).

**Why it matters:** Without Security Hub, security findings are scattered across 5+ AWS service consoles. Investigators waste hours pivoting. With Security Hub, you have one queue ranked by severity, aged, and assigned. AFSBP specifically is the AWS-curated set of "if you do these 200 things, you're not embarrassingly insecure" controls — orders of magnitude more actionable than the generic CIS benchmark for cloud-native orgs.

**Pricing:** ~$0.0010 per security check, ~$5-15/month at startup scale. Pay-per-finding-evaluation.

**What breaks if you skip it:** Security findings are siloed. No central queue. No compliance score trending over time. Auditors ask "what was your Security Hub score 6 months ago?" and you have no answer.

**When to graduate off it:** Never. At enterprise scale, layer in additional standards (CIS, PCI-DSS, NIST 800-53) only when contractually required.

**References:**
- [AWS Security Hub user guide](https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html)
- [AWS Foundational Security Best Practices controls](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp.html)

---

## Control 7 — IAM Access Analyzer

**What it does:** Continuously evaluates resource policies (S3 buckets, IAM roles, KMS keys, Lambda functions, Secrets Manager secrets, SQS queues, SNS topics) and surfaces any that grant access to entities outside your AWS account.

**AWS resources:** `aws_accessanalyzer_analyzer` (account scope).

**Configuration choices:** Account-scope analyzer (free). Organization-scope analyzers require AWS Organizations; that's post-seed-stage.

**Why it matters:** It is shockingly easy to write an IAM role trust policy that accidentally grants assume-role to `"AWS": "*"` instead of `"AWS": "arn:aws:iam::123456789012:root"`. Same for cross-account S3 bucket policies. Access Analyzer catches these the moment they're created.

**What breaks if you skip it:** Cross-account access drift goes unnoticed. The classic "we gave a vendor access to one bucket 18 months ago and never revoked it" finding never surfaces.

**When to graduate off it:** Never disable the account-scope analyzer (it's free). Add an organization-scope analyzer when you adopt AWS Organizations.

**References:**
- [AWS — IAM Access Analyzer user guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)

---

## Control 8 — Default EBS encryption

**What it does:** Sets a region-wide default that every NEW EBS volume created is encrypted at rest using the AWS-managed KMS key.

**AWS resources:** `aws_ebs_encryption_by_default`.

**Configuration choices:** Uses AWS-managed `alias/aws/ebs` key (free). Customer-managed key is an option but adds key-management overhead with marginal security benefit at this stage.

**Why it matters:** Without default encryption, developers must remember to specify `encrypted = true` on every EBS volume. They will forget. The first time you have a stolen EBS snapshot or a misconfigured cross-account share, you'll wish every disk had been encrypted by default.

**What breaks if you skip it:** Existing EBS volumes are NOT retroactively encrypted (you'd need snapshot+restore for those). New volumes created without explicit `encrypted = true` are unencrypted at rest.

**Caveat:** This setting is region-scoped. If you operate in multiple regions, apply this module in each region (or set `encrypted = true` explicitly in your EC2 launch templates as a backstop).

**When to graduate off it:** Never disable. Optionally migrate to a customer-managed CMK if your compliance regime requires key custody.

**References:**
- [AWS — Encryption by default](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html#encryption-by-default)

---

## Control 9 — Default VPC Flow Logs

**What it does:** Captures network metadata (source/dest IP + port, protocol, bytes, accept/reject) for traffic in your default VPC, sent to CloudWatch Logs.

**AWS resources:**
- `data.aws_vpc.default`
- `aws_cloudwatch_log_group`
- `aws_iam_role` + `aws_iam_role_policy` (delivery role)
- `aws_flow_log`

**Configuration choices:**
- `traffic_type = "REJECT"` — log only dropped traffic. Half the cost of `ALL`, ~10x more useful for security investigation (rejected traffic = port scans, attempted exfiltration, misconfigured services). Switch to `"ALL"` if you need full visibility for compliance.
- `flow_log_retention_days = 90` — covers most incident-investigation windows. Override for compliance regimes that mandate longer retention.

**Why it matters:** When something goes wrong networkwise — an EC2 instance reaching out to a known-malicious IP, an internal service unable to reach an external API, a port scan — flow logs are the only record. Real-time inspection is impossible without them.

**What breaks if you skip it:** No network forensics for the default VPC. If your team launches EC2/RDS/ECS in the default VPC (which they will, despite your best efforts), there's no audit trail when one of those resources gets compromised.

**Caveat:** Many startups never use the default VPC — everything goes in a custom VPC managed elsewhere. In that case, set `enable_default_vpc_flow_logs = false` and configure flow logs on your custom VPCs separately.

**When to graduate off it:** When you've fully eliminated the default VPC (best practice) or when you have org-wide VPC Flow Logs aggregated into a central S3 bucket via a separate IaC stack.

**References:**
- [AWS — VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)

---

## Control 10 — AWS Config recorder (high-blast-radius types only)

**What it does:** Records every configuration change to a defined set of AWS resource types, with full before/after diffs and the IAM principal who made the change.

**AWS resources:**
- `aws_iam_role` + `aws_iam_role_policy_attachment` (Config service role)
- `aws_s3_bucket` for snapshots (private, versioned, public-access-blocked)
- `aws_s3_bucket_policy`
- `aws_config_configuration_recorder`
- `aws_config_delivery_channel`
- `aws_config_configuration_recorder_status` (starts the recorder)

**Configuration choices:**
- `config_record_all = false` (default) — records only IAM users/roles/policies/groups, S3 buckets, security groups, NACLs, VPCs, KMS keys. The "high-blast-radius" set: resources that, if misconfigured, can cause an immediate security incident. Cost: ~$2/month at startup scale.
- Set `config_record_all = true` to record every supported resource type. Cost: ~$10-30/month.
- `delivery_frequency = "TwentyFour_Hours"` — daily snapshots delivered to S3. Continuous change events are still emitted in real time; this is just the periodic full-snapshot cadence.

**Why it matters:** "Who changed this IAM policy and when?" is one of the most common incident-response questions. CloudTrail tells you the API call happened; Config tells you the *before* and *after* of the resource. Together they give complete change history.

**What breaks if you skip it:** Forensics is reduced to "let's read the Terraform git history and hope nobody clicked in the console." Config rule evaluations (e.g., automated SOC 2 evidence) are impossible without the recorder running.

**When to graduate off it:** When you've adopted AWS Organizations and have an org-wide aggregator in your management account. Until then, account-scope Config is the right level.

**References:**
- [AWS Config user guide](https://docs.aws.amazon.com/config/latest/developerguide/WhatIsConfig.html)

---

## Control 11 — Cost Anomaly Detection

**What it does:** ML-based detection of unusual AWS spend per service, with email subscription on findings above a configurable USD threshold.

**AWS resources:** `aws_ce_anomaly_monitor` (DIMENSIONAL, SERVICE) + `aws_ce_anomaly_subscription`.

**Configuration choices:**
- `monitor_dimension = "SERVICE"` — flags anomalies per AWS service. Catches "EC2 spend doubled overnight because someone launched a g5.4xlarge."
- `cost_anomaly_threshold_usd = 100` — minimum impact for an alert. At seed-stage spend (<$10k/month), $100 is a meaningful spike. Raise to $500-1000 once you're at >$10k/mo to cut noise.
- `frequency = "DAILY"` — most-aggressive cadence. Same-day visibility into surprise charges.

**Why it matters:** Catches the 11pm-on-Friday "we left a $2/hour GPU instance running over the weekend" situation before Monday morning. Cost anomalies are the leading indicator of (a) operational mistakes, (b) compromised credentials being used to mine cryptocurrency, (c) unexpected scaling. All three you want to know about within 24 hours, not 30 days when the bill arrives.

**What breaks if you skip it:** First indication of cost issues comes from the monthly bill. Founders learn about $10k surprise charges via email from AWS Billing, which is the worst possible time and posture.

**When to graduate off it:** Never. Add additional monitors (per-account, per-cost-allocation-tag, per-region) at scale.

**References:**
- [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html)

---

## Control 12 — AWS Budgets monthly cap

**What it does:** Tracks actual monthly AWS spend against a declared cap, with email + SNS notifications at configurable percentage thresholds.

**AWS resources:** `aws_budgets_budget` (cost-monthly with notification blocks).

**Configuration choices:**
- `budget_alert_thresholds_pct = [80, 100]` — warning at 80%, critical at 100%. Optionally add `[50, 80, 100, 120]` for more granular tracking.
- Notifications go to BOTH `subscriber_email_addresses` (direct from AWS Budgets) AND `subscriber_sns_topic_arns` (the alerts SNS topic). Belt + suspenders.
- `budget_type = "COST"` — actual spend, not forecasted. Forecast budgets generate too many false alerts at variable workloads.

**Why it matters:** Budgets is a hard ceiling-with-alarm. Cost Anomaly catches *anomalies* in normal spend; Budgets catches *normal spend that's higher than your runway can absorb*. Different problems, both worth solving.

**What breaks if you skip it:** No early warning when normal-pattern spend is higher than expected. Founders find out at the next CFO budget review.

**When to graduate off it:** Never. Add per-team or per-product budgets via cost allocation tags as the org grows.

**References:**
- [AWS Budgets user guide](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)

---

## Adding a new control

If you have a candidate for the baseline that meets all four criteria — universal applicability to seed-stage startups, low setup cost (<$5/month), low operational overhead (no babysitting), and a clear "what breaks if you skip" answer — open a PR. Use this same template structure when documenting it.

The bar is intentionally high: every control we add is one more thing every adopter has to maintain. The goal is "smallest baseline that prevents the largest share of incidents" — not "every CIS control."
