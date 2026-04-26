# Changelog

All notable changes to this module are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-26

### Added
- Initial public release.
- 12 AWS security controls covering IAM password policy, root MFA enforcement
  alarm, multi-region CloudTrail (with KMS encryption + log file validation),
  S3 account-level public access block, GuardDuty, Security Hub + AFSBP
  standard, IAM Access Analyzer, default EBS encryption, default-VPC Flow
  Logs, AWS Config recorder (high-blast-radius types only), Cost Anomaly
  Detection, and AWS Budgets monthly threshold alerts.
- SNS topic + 4 CloudWatch metric alarms for security-event notifications,
  emailed to a single configurable address.
- Two examples: `examples/minimal/` (greenfield account) and
  `examples/with-existing-cloudtrail/` (brownfield with pre-existing trail).
- Per-control rationale + AWS doc citations in `docs/controls.md`.
- Honest scope-out list in `docs/what-this-doesnt-cover.md`.
- GuardDuty finding response runbook in `docs/runbooks/`.
- CI workflow running `terraform fmt -check`, `terraform validate`, `tflint`,
  and `tfsec` on every push and PR.

[Unreleased]: https://github.com/avinash-matrixgard/aws-startup-security-baseline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/avinash-matrixgard/aws-startup-security-baseline/releases/tag/v0.1.0
