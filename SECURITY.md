# Security Policy

This module provisions AWS security infrastructure. Bugs in it can have direct security impact for adopters. We treat security reports with priority.

## Reporting a vulnerability

**Please do NOT open a public GitHub issue for security vulnerabilities.**

Instead, report privately via one of these channels:

1. **Preferred:** [GitHub Private Vulnerability Reporting](https://github.com/avinash-matrixgard/aws-startup-security-baseline/security/advisories/new) — encrypted, GitHub-mediated.
2. **Email:** `security@matrixgard.com` (encrypted preferred — request a PGP key in your initial mail and we'll respond with one before you send sensitive details).

Include in your report:

- A clear description of the issue (what control / which file / what scenario).
- Reproduction steps or proof-of-concept (Terraform snippet, AWS CLI commands, etc.).
- Impact assessment: who is affected, what's the worst case.
- Your proposed fix, if you have one.
- Whether you'd like credit in the disclosure (and the name / handle to use).

## Response timeline

| Stage | Target |
|-------|--------|
| Acknowledgement | within **48 hours** of receipt |
| Initial assessment + severity rating | within **5 business days** |
| Patch developed + tested | within **30 days** for HIGH/CRITICAL, **60 days** for MEDIUM, **90 days** for LOW |
| Public disclosure | coordinated with reporter — typically within 14 days of patch release |

We follow responsible-disclosure best practice. We'll keep you informed at each stage and never publicly disclose your report before the patch is available unless you explicitly request earlier disclosure.

## Scope

In scope:

- Any code in `modules/`, `examples/`, or `scripts/` that creates insecure AWS resources, leaks credentials, or weakens the security posture it claims to strengthen.
- CI workflows in `.github/workflows/` that could be exploited (action injection, secret leakage, SHA tampering).
- Any documentation in `README.md`, `docs/`, or `modules/*/README.md` that misleads adopters into a less-secure configuration than they think they're getting.

Out of scope (please don't report these as vulnerabilities):

- Security best-practices we explicitly skip (see the [skip list in README](README.md#whats-deliberately-out-the-skip-list)) — those are documented design choices, not bugs.
- Generic AWS service vulnerabilities (report to AWS directly via aws-security@amazon.com).
- Issues in the AWS provider itself (report to [hashicorp/terraform-provider-aws](https://github.com/hashicorp/terraform-provider-aws/security)).
- Findings from generic security scanners (tfsec, Checkov, Trivy) on the example code that don't represent real risk in the documented usage pattern. Open a regular issue for these.

## Supported versions

Only the latest released minor version receives security patches. Older versions are EOL.

| Version  | Supported          |
|----------|--------------------|
| 0.1.x    | :white_check_mark: |
| < 0.1.0  | :x:                |

## Hall of fame

We credit security researchers who report responsibly. Once we have our first valid disclosure, this section will list contributors.

---

**Maintainer:** [MatrixGard](https://matrixgard.com) — `security@matrixgard.com`.
