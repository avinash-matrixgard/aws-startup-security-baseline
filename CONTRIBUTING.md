# Contributing

Thanks for considering a contribution. This module is opinionated by design — please read this short guide before opening a PR so we can move quickly together.

## The bar

Every new control must come with **all four** of the following, in the README's tables and in `docs/controls.md`:

1. **What it does** — one-sentence description, plain English.
2. **Why we add it** — what real-world failure mode it prevents. Cite an AWS doc, NIST control, or public incident if possible.
3. **What breaks if you skip it** — the honest "you will eventually regret skipping this because..." paragraph.
4. **When to graduate off it** — when an org has outgrown the control's value (e.g., "after migrating to AWS Organizations" or "once you have a dedicated security engineer").

PRs that add controls without all four sections will be asked to add them before merge.

## What we will NOT accept

- Adding controls "because CIS says so" without explaining the seed-stage tradeoff.
- Adding paid/expensive AWS services (WAF, Macie, Network Firewall, Detective, Audit Manager) to the default baseline. Discuss in an issue first — these likely belong as opt-in submodules, not core.
- Removing the "skip list" entries. Those are the differentiator.
- Vague "improvements" without a working example demonstrating the change.

## Local development

```bash
# Install pre-reqs (macOS)
brew install terraform tflint tfsec pre-commit

# Run formatters + linters before committing
terraform fmt -recursive
terraform validate
tflint --recursive
tfsec .
```

## PR checklist

- [ ] `terraform fmt -recursive` is clean
- [ ] `terraform validate` passes for `modules/baseline/` and every example
- [ ] `tflint --recursive` is clean (or new ignores have a comment explaining why)
- [ ] `tfsec .` is clean (or new ignores have a `tfsec:ignore:RULE_ID` line and a one-line justification comment)
- [ ] If a new control was added: README table + `docs/controls.md` entry + (if needed) skip-list update
- [ ] `CHANGELOG.md` "Unreleased" section updated
- [ ] No `*.tfvars` or `*.tfstate` files committed (see `.gitignore`)

## Reporting issues

When filing an issue, please include:

- Terraform version (`terraform version`)
- AWS provider version (from `.terraform.lock.hcl`)
- AWS region
- The exact `terraform apply` error output, redacted of account IDs / ARNs

## License

By contributing, you agree your contributions will be licensed under the MIT License (see [LICENSE](LICENSE)).

## Maintainer

[MatrixGard](https://matrixgard.com) — avinash@matrixgard.com.
