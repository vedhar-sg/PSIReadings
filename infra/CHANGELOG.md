# Changelog

All notable changes to the OutSystems 11 AWS infrastructure (`infra/`) are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and releases are tagged `infra-vMAJOR.MINOR.PATCH` (see README "Contributing and versioning").

## [Unreleased]

## [1.0.0] - 2026-10-22

### Added
- Account bootstrap: KMS-encrypted, versioned S3 state bucket with native locking
  (optional DynamoDB table), Auto Scaling service-linked role, GitHub OIDC
  provider and plan/apply roles.
- Modules: `network`, `security`, `database`, `edge`, `platform`,
  `observability` (including a daily SSM patch compliance scan) and `dr-backup`.
- Shared `stack/` root with per-environment `envs/<env>/backend.hcl` and
  `terraform.tfvars` for dev, test, lifetime and prod.
- Environment guardrails (`stack/guardrails.tf`) that fail a plan when prod or
  LifeTime settings drop below the baseline.
- Automated tests: `terraform test` suites for bootstrap, every module and the
  stack (per environment, including negative guardrail cases) using mocked
  providers.
- Tooling: `Makefile`, `scripts/tf.sh` / `scripts/tf.ps1` wrappers,
  `scripts/test.sh` validation suite, pre-commit hooks, tflint, Checkov and
  terraform-docs configuration.
- GitHub Actions workflow: validation on every change, plan per environment on
  pull requests, approval-gated sequential apply on `main`.
- Documentation: architecture, setup, deployment, OutSystems installation,
  operations runbooks, troubleshooting and contribution guide.
