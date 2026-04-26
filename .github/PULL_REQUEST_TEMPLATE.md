<!--
Thanks for the contribution. A few quick checks below.
Anything you can't fill in yet, leave as-is and we'll work on it together in review.
-->

## What

<!-- One-paragraph summary of what this PR changes -->

## Why

<!-- Link to the issue / discussion / external context that motivated the change -->

Fixes #

## Type of change

- [ ] New control (adds an AWS resource or alarm)
- [ ] Documentation only
- [ ] Bug fix (non-breaking)
- [ ] Bug fix (breaking — input/output schema changed)
- [ ] Refactor (no behavior change)
- [ ] CI / tooling

## Checklist

- [ ] `terraform fmt -recursive` is clean
- [ ] `terraform validate` passes for `modules/baseline/` and every example I touched
- [ ] `tflint --recursive` is clean (or new ignores include a comment)
- [ ] `tfsec .` is clean (or new `tfsec:ignore:RULE_ID` lines have one-line justification comments)
- [ ] If a new control was added: README table + `docs/controls.md` entry following the existing template (What it does / Why it matters / What breaks if you skip / When to graduate off)
- [ ] `CHANGELOG.md` "Unreleased" section updated
- [ ] No `*.tfvars` or `*.tfstate` committed (see `.gitignore`)
- [ ] If GitHub Actions were added/updated: pinned to a commit SHA, not a version tag

## Tested with

<!-- Terraform version + AWS provider version + region you tested in -->

- Terraform:
- AWS provider:
- Region:

## Screenshots / output

<!-- If relevant: terraform plan diff, console screenshot, etc. -->
