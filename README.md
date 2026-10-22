# PSIReadings

Infrastructure for hosting the OutSystems 11 platform on AWS, which runs the PSI readings / SGDataExplorer application.

| Path | What |
|---|---|
| [`infra/`](infra/README.md) | Terraform for the Dev, Test, Prod and LifeTime environments, plus tests, runbooks and the task runner. Start with [infra/README.md](infra/README.md). |
| `.github/workflows/infra-terraform.yml` | CI/CD: validation, a plan per environment on PRs, and approval-gated apply on `main`. |
| `.pre-commit-config.yaml` | Local hooks: fmt, validate, tflint, Checkov, terraform-docs and secret detection. |

Quick check, with no AWS credentials needed:

```bash
cd infra
make check
```
