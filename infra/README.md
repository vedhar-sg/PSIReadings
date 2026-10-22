# OutSystems 11 on AWS — Terraform

Production-ready Infrastructure as Code for a **self-managed OutSystems 11** installation on AWS: the Dev, Test and Prod environments plus a dedicated LifeTime environment.

- **Compute:** each environment runs a Platform Server controller and front-ends on Windows EC2, behind an Application Load Balancer with WAF and TLS.
- **Database:** Amazon RDS for SQL Server (Oracle is optional) holds the platform database.
- **Delivery:** everything is versioned in Git, tested offline with `terraform test`, and deployed through an approval-gated GitHub Actions pipeline.

## Contents

1. [Architecture](#architecture)
2. [Repository layout](#repository-layout)
3. [Prerequisites and tooling](#prerequisites-and-tooling)
4. [Quick start](#quick-start)
5. [Bootstrap the state backend](#1-bootstrap-the-state-backend-once-per-aws-account)
6. [Configure an environment](#2-configure-an-environment)
7. [Deploy](#3-deploy)
8. [Set the secrets](#4-set-the-secrets)
9. [Install OutSystems 11](#5-install-outsystems-11-post-provisioning)
10. [CI/CD pipeline](#cicd-pipeline)
11. [Testing and validation](#testing-and-validation)
12. [Operations runbooks](#operations-runbooks)
13. [Destroying an environment](#destroying-an-environment)
14. [Troubleshooting](#troubleshooting)
15. [Contributing and versioning](#contributing-and-versioning)
16. [Known limitations](#known-limitations)

## Architecture

```
                    Internet / VPN
                          │ 443
                   ┌──────▼──────┐   WAFv2 (managed rules + rate limit)
                   │     ALB     │   ACM certificate, HTTP→HTTPS redirect
                   └──┬───────┬──┘   (public subnets, 2–3 AZs)
          app traffic │       │ (single-server envs only)
        ┌─────────────▼─┐   ┌─▼──────────────┐
        │ Front-end ASG │◄─►│   Controller   │  Deployment Controller,
        │ Windows 2022  │   │  Windows 2022  │  RabbitMQ cache invalidation
        └───────┬───────┘   └───────┬────────┘  (private subnets, NAT egress)
                │ 1433              │ 1433
              ┌─▼───────────────────▼─┐
              │ RDS SQL Server (KMS)  │  Multi-AZ in prod, isolated subnets
              └───────────────────────┘
   CloudWatch agent → log groups · alarms → SNS · AWS Backup → DR region
```

Each environment is a separate instance of the same `stack/` root, with its own:

- VPC, KMS key, secrets, ALB, controller, front-end Auto Scaling group and RDS instance;
- Terraform state file.

LifeTime is a single-server environment that manages the other three.

### Environment defaults

| | dev | test | lifetime | prod |
|---|---|---|---|---|
| AZs / NAT | 2 / shared | 2 / shared | 2 / shared | 3 / one per AZ |
| Controller | m6i.xlarge, also serves apps | m6i.xlarge | m6i.xlarge, also serves apps | m6i.xlarge |
| Front-ends (min/max) | m6i.large 0/2 | m6i.large 1/3 | none | m6i.xlarge 2/6 |
| RDS | SE db.m6i.large | SE db.m6i.large | SE db.m6i.large | SE db.m6i.xlarge Multi-AZ |
| WAF | count | count | block | block |
| Deletion protection | off | DB only | on | on |
| Cross-region backup copy | off | off | on | on |
| Log retention | 30 d | 60 d | 90 d | 365 d |

The guardrails in [`stack/guardrails.tf`](stack/guardrails.tf) **fail the plan** if prod drops below:

- Multi-AZ RDS, deletion and termination protection, 3 AZs, a NAT gateway per AZ and at least two front-ends;
- WAF in block mode;
- cross-region backup copies, ≥30 days of point-in-time recovery and 365 days of logs.

LifeTime must stay deletion-protected and copied cross-region.

### Security model

- **No credentials in code, tfvars, user data or state.**
  - The RDS master password is generated and rotated by RDS in Secrets Manager.
  - Every other OutSystems credential is an **empty Secrets Manager placeholder that an operator fills in**.
  - Instances only receive the secrets' ARNs.
- **Encryption:** each environment has a customer-managed KMS key with rotation. It encrypts EBS, RDS, the secrets, log groups, SNS and the backup vaults. The state bucket has its own key.
- **No inbound admin ports.** Administration goes through SSM Session Manager and Fleet Manager. Servers are in private subnets. Database subnets have no internet route.
- **Security groups** follow OutSystems roles:
  - ALB → front-ends on 443.
  - Controller → front-ends on 12001.
  - Front-ends → controller on 12000, 5672 and 443.
  - Servers → RDS on 1433.
- **TLS 1.2/1.3** on the ALB, HTTP→HTTPS redirect, invalid headers dropped, IMDSv2 required.
- **WAF:** AWS managed rule groups plus a per-IP rate limit. `SizeRestrictions_BODY` is downgraded to count so solution uploads to Service Center and LifeTime work.
- **CI** uses GitHub OIDC (no stored AWS keys). Apply only runs inside approval-gated GitHub Environments.
- **Account guard:** `allowed_account_ids` makes Terraform refuse to run against the wrong account.

## Repository layout

| Path | Purpose |
|---|---|
| `bootstrap/` | One-off per AWS account: state bucket (+ optional DynamoDB lock table), Auto Scaling service-linked role, GitHub OIDC provider, CI plan/apply roles. |
| `stack/` | Root module for **one** environment: wires the modules together and holds the guardrails. |
| `modules/network` | VPC, public / private / isolated DB subnets, NAT, VPC endpoints, flow logs. [Docs](modules/network/README.md) |
| `modules/security` | KMS key, instance IAM role/profile, Secrets Manager placeholders. [Docs](modules/security/README.md) |
| `modules/database` | RDS SQL Server / Oracle with an RDS-managed master secret. [Docs](modules/database/README.md) |
| `modules/edge` | ACM certificate and WAFv2 web ACL. [Docs](modules/edge/README.md) |
| `modules/platform` | Security groups, ALB, controller, front-end launch template and ASG. [Docs](modules/platform/README.md) |
| `modules/observability` | CloudWatch agent via SSM, alarms, SNS, dashboard, auto-recovery, patch scan. [Docs](modules/observability/README.md) |
| `modules/dr-backup` | AWS Backup vault and plan, with optional cross-region copy. [Docs](modules/dr-backup/README.md) |
| `*/tests/*.tftest.hcl` | `terraform test` suites (mocked providers; no credentials needed). |
| `envs/<env>/backend.hcl` | Where the environment's state lives (bucket, key, region, locking). |
| `envs/<env>/terraform.tfvars` | The environment's sizing and settings. **Committed; must never contain secrets.** |
| `scripts/tf.sh`, `scripts/tf.ps1` | Run Terraform for one environment with the matching backend + tfvars and an isolated `.terraform` directory. |
| `scripts/test.sh` | The full offline validation suite (used by `make check`, pre-commit and CI). |
| `Makefile` | Task runner: `init`, `plan`, `apply`, `test`, `lint`, `scan`, `docs`, `check`, … |
| `.tflint.hcl`, `.checkov.yaml`, `.terraform-docs.yml` | Linter, security scanner and doc-generator configuration. |
| `CHANGELOG.md` | Release history. |
| `../.pre-commit-config.yaml` | Pre-commit hooks (fmt, validate, tflint, Checkov, terraform-docs, secret detection). |
| `../.github/workflows/infra-terraform.yml` | CI/CD pipeline. |

## Prerequisites and tooling

| Tool | Version | Used for |
|---|---|---|
| Terraform | `>= 1.10` (CI pins **1.13.5**) | Everything. 1.10+ is required for native S3 state locking. |
| AWS provider | `~> 6.0`, locked to **6.70.0** in `.terraform.lock.hcl` | AWS resources |
| AWS CLI v2 | current | Bootstrap, setting secrets, runbooks. Sign in with IAM Identity Center (`aws sso login`), not static keys. |
| tflint | 0.64.0 + AWS ruleset 0.40.0 | Linting |
| Checkov | 3.x | Security scanning |
| terraform-docs | 0.19.0 | Module documentation |
| pre-commit | 3.x | Local hooks |
| GNU Make, Bash | any | `Makefile` and `scripts/*.sh`. On Windows use Git Bash or WSL, or `scripts/tf.ps1` for deployments. |

No local tooling? Every check also runs in Docker; see [Testing and validation](#testing-and-validation).

You also need:

- **AWS accounts.** By default prod is in its own account; dev, test and lifetime share a non-prod account.
- **TLS for each environment:** either a public Route 53 hosted zone for its domain (automatic ACM validation), or an existing ACM certificate (`certificate_arn`).
- The **OutSystems 11 Platform Server installer** and a **licence per environment**, from your OutSystems account. Terraform doesn't download or install OutSystems.
- A database edition and version on the OutSystems 11 **system requirements** list for your Platform Server version. RDS SQL Server Standard, licence-included, is the default.

## Quick start

```bash
cd infra
make check                      # offline: fmt, validate, tests, lint, scan, docs
# one-off per account:
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars   # edit placeholders
make bootstrap-plan && make bootstrap-apply
# per environment:
$EDITOR envs/dev/backend.hcl envs/dev/terraform.tfvars              # replace REPLACE values
make init ENV=dev
make plan ENV=dev
make apply ENV=dev              # applies only the reviewed dev.tfplan
```

## 1. Bootstrap the state backend (once per AWS account)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # account ID, bucket name, owner/repo
terraform init
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

What it creates:

- **State bucket:** versioned, KMS-encrypted, public access blocked, TLS-only, old versions expire after 90 days.
- **Locking:** native S3 locking (`use_lockfile = true`). A DynamoDB lock table is available with `create_dynamodb_lock_table = true`; HashiCorp has deprecated DynamoDB locking, so it's off by default.
- **`AWSServiceRoleForAutoScaling`.** If it already exists, set `create_autoscaling_service_linked_role = false`.
- **GitHub OIDC provider.** If one already exists, set `create_github_oidc_provider = false`.
- **CI roles:**
  - `outsystems-terraform-plan`: `ReadOnlyAccess` plus state access. Trusted for PRs and `main`.
  - `outsystems-terraform-apply`: trusted **only** for jobs in the GitHub Environments `dev`, `test`, `lifetime` and `prod`. It defaults to `AdministratorAccess`; replace it with a scoped policy through `apply_role_policy_arns` once the resource set is stable.

Notes:

- Run bootstrap again in the prod account, with its own bucket name.
- Bootstrap state is local. Keep `bootstrap/terraform.tfstate` safe, or migrate it into the new bucket:
  1. Add `backend "s3" {}`.
  2. Run `terraform init -migrate-state -backend-config=...`.

## 2. Configure an environment

1. Copy the bootstrap output `state_bucket` into `envs/<env>/backend.hcl`.
2. In `envs/<env>/terraform.tfvars`, replace every `REPLACE`:
   - `allowed_account_ids`;
   - either `domain_name` + `route53_zone_id`, or `certificate_arn`.
3. Optional settings (`stack/variables.tf` lists them all):
   - `alarm_emails` — each recipient confirms the SNS subscription;
   - `alb_ingress_cidrs` — strongly recommended for LifeTime and non-prod;
   - `ami_id` / `frontend_ami_id`;
   - `installer_bucket_arn`;
   - `extra_readable_secret_arns`;
   - `target_protocol`;
   - `health_check_path`.

Settings changes are ordinary Git changes: open a PR, review the plan, merge.

## 3. Deploy

Always use the wrappers (`make`, `scripts/tf.sh` or `scripts/tf.ps1`). They:

- pair `envs/<env>/backend.hcl` with `envs/<env>/terraform.tfvars`;
- refuse to run if the backend key names a different environment;
- keep a separate `.terraform-<env>` directory, so switching environments never re-points the backend.

```bash
make init ENV=dev
make plan ENV=dev          # writes stack/dev.tfplan; review it
make apply ENV=dev         # applies exactly that plan
make output ENV=dev
```

On Windows PowerShell:

```powershell
.\scripts\tf.ps1 dev init
.\scripts\tf.ps1 dev plan -out dev.tfplan
.\scripts\tf.ps1 dev apply dev.tfplan
```

- Deploy in the order `lifetime`, `dev`, `test`, `prod`.
- A first apply takes roughly 30–60 minutes. RDS SQL Server and Multi-AZ are the slow parts.
- Afterwards, point the environment's DNS name at the `alb_dns_name` output (a Route 53 alias, using `alb_zone_id`).

## 4. Set the secrets

The placeholder secrets (`placeholder_secret_arns` output) are created **empty**. Populate them yourself in the Secrets Manager console, or:

```bash
aws secretsmanager put-secret-value --secret-id os11-dev/outsystems/rabbitmq --secret-string file://rabbitmq.json
```

Use a JSON shape such as `{"username":"...","password":"..."}`. Create the file outside the repository and delete it afterwards; `*.secrets.json`, `.env` and similar files are git-ignored as a safety net.

The RDS master credentials are already in the secret named by `database_master_secret_arn`.

## 5. Install OutSystems 11 (post-provisioning)

Reach servers without exposing RDP:

- **SSM Session Manager** (PowerShell, no password). Use it to set a local administrator password yourself.
- **Fleet Manager → Remote Desktop**, with that password or IAM Identity Center SSO.

User data has already installed the IIS and .NET features and written `C:\ProgramData\OutSystemsBootstrap\environment.json`. It holds the environment, role, controller IP, database host and port, and the secret **ARNs**.

### Controller (every environment, including LifeTime)

1. Copy the Platform Server installer onto the instance (from your OutSystems downloads, or from `installer_bucket_arn`). Run it, including the prerequisites and RabbitMQ (Cache Invalidation Service).
2. In the **Configuration Tool**:
   - **Database**: SQL Server, server = `database_address` output, port 1433, SQL authentication.
     - For **Create/Upgrade Database**, use the RDS master credentials.
     - Set the admin, runtime, log and session users to the values in the `db-*` secrets.
   - **Controller**: this server is the Deployment Controller.
   - **Cache Invalidation Service**: local RabbitMQ, with the `rabbitmq` secret's user.
   - **Apply and Exit**, then install **Service Center**.
3. Bind a certificate to the IIS HTTPS (443) site. A self-signed one is fine, because the ALB doesn't validate target certificates. Alternatively set `target_protocol = "HTTP"`.
4. Open `https://<domain>/ServiceCenter`:
   - change the admin password to the one in the `platform-admin` secret;
   - upload the environment licence;
   - install **System Components**.
5. **LifeTime only:** install the **LifeTime Management Console** solution.
6. Back up `server.hsconf` and `private.key` from `C:\Program Files\OutSystems\Platform Server\`. **All servers in an environment share the same `private.key`.**
   - Store it yourself as a secret.
   - Add that secret's ARN to `extra_readable_secret_arns` if bootstrap automation will read it.

### Front-ends

1. Install the same Platform Server version.
2. Copy `server.hsconf` and `private.key` from the controller.
3. In the Configuration Tool, set **Deployment Controller** to `controller_private_ip`.
4. In Service Center → **Administration → Servers**, confirm the server registered and is enabled. The controller then deploys every application to it.

For hands-off scaling, build a **golden AMI** (see the [AMI runbook](#golden-ami-and-instance-replacement)) and set `frontend_ami_id` and `enable_launch_lifecycle_hook = true`.

### Register environments in LifeTime

In LifeTime → **Environments → Add environment**, register Dev, Test and Prod by their HTTPS URLs.

If `alb_ingress_cidrs` is restricted, include the LifeTime NAT IPs (the `nat_public_ips` output).

### Health check

Once applications exist, change `health_check_path` from `/` to a lightweight page of a deployed module. The ALB then detects broken Platform Server installs, not just a stopped IIS.

## CI/CD pipeline

[`.github/workflows/infra-terraform.yml`](../.github/workflows/infra-terraform.yml):

| Trigger | Jobs |
|---|---|
| Any PR or push touching `infra/` | **validate**: `terraform fmt -check`, `validate` (every root and module), `terraform test` (bootstrap, every module, and the stack against each environment's tfvars), tflint, Checkov, terraform-docs drift check |
| Pull request | **plan** per environment with the read-only role; plan text in the job summary and as an artifact |
| Push to `main` | **apply** environment by environment (`dev` → `test` → `lifetime` → `prod`). Each job runs inside its GitHub Environment, so it **waits for manual approval**, re-plans and applies that plan. A failure stops later environments. |
| `workflow_dispatch` | Plan and apply one chosen environment, still approval-gated |

One-time GitHub setup:

1. Create the Environments `dev`, `test`, `lifetime` and `prod`. Add **required reviewers** to each, at least to `prod`. Optionally restrict them to the `main` branch.
2. Set these Actions variables (not secrets; they're role ARNs):
   - Repository: `AWS_PLAN_ROLE_ARN`, or per environment `AWS_PLAN_ROLE_ARN_DEV`, `_TEST`, `_LIFETIME`, `_PROD`. Prod's role lives in the prod account.
   - Each environment: `AWS_APPLY_ROLE_ARN`.
3. Protect `main`: require PR review and the `fmt / validate / test / lint / scan / docs` check.

Reproducibility in CI:

- Terraform, tflint and terraform-docs versions are pinned.
- `init -lockfile=readonly` refuses provider versions that differ from the committed lock files.

## Testing and validation

Everything runs offline, with no AWS credentials and nothing created.

| Layer | What it checks | Command |
|---|---|---|
| Format | Canonical HCL formatting | `scripts/test.sh fmt` |
| Validate | Every root and standalone module is internally consistent (`dr-backup` needs its caller's `aws.dr` provider, so the stack covers it) | `scripts/test.sh validate` |
| Unit tests | Per-module behaviour with a mocked AWS provider, e.g.: <br>• DB is never public and the password is RDS-managed <br>• IMDSv2 required; EBS encrypted <br>• OutSystems ports only between roles <br>• scale-in off by default <br>• WAF modes, and uploads not blocked <br>• a scan-only patch association exists <br>• cross-region backups <br>• state bucket hardening | `scripts/test.sh test` |
| Stack tests | The full stack plans with each environment's real tfvars; guardrails reject unsafe prod/LifeTime settings (negative tests) | `scripts/test.sh test` |
| Lint | tflint, Terraform and AWS rulesets (invalid instance types, deprecated syntax, unused declarations, …) | `scripts/test.sh lint` |
| Security scan | Checkov. Accepted findings are skipped inline or in `.checkov.yaml`, each with a reason | `scripts/test.sh scan` |
| Docs | Module READMEs match the code | `scripts/test.sh docs` |

Run everything with `make check` (or `scripts/test.sh`).

Test suites live next to the code they test:

- `modules/*/tests/*.tftest.hcl`
- `bootstrap/tests/`
- `stack/tests/`

A single suite:

```bash
terraform -chdir=modules/platform init -backend=false
terraform -chdir=modules/platform test
terraform -chdir=stack test -var-file=../envs/prod/terraform.tfvars
```

Without local tools, use Docker:

```bash
cd infra
TF_CMD="docker run --rm -v $PWD:/work -w /work hashicorp/terraform:1.13.5" \
TFLINT_CMD="docker run --rm -v $PWD:/data -v tflint-plugins:/plugins -e TFLINT_PLUGIN_DIR=/plugins -w /data ghcr.io/terraform-linters/tflint:v0.64.0" \
TFLINT_CONFIG=/data/.tflint.hcl \
CHECKOV_CMD="docker run --rm -v $PWD:/tf -w /tf bridgecrew/checkov:3" \
TFDOCS_CMD="docker run --rm -v $PWD:/work -w /work quay.io/terraform-docs/terraform-docs:0.19.0" \
scripts/test.sh
```

### Pre-commit

```bash
pip install pre-commit
pre-commit install            # runs on every commit touching infra/
pre-commit run --all-files
```

The hooks run, in order:

1. fmt
2. validate
3. tflint
4. Checkov
5. terraform-docs
6. private-key and AWS-credential detection
7. whitespace and YAML checks

## Operations runbooks

Run every change through Git and the pipeline, except the emergency steps marked as such.

### Scaling

- **Front-ends scale out automatically** on CPU (`cpu_target_percent`) and requests per target (`requests_per_target`).
- **Change capacity limits** with `frontend_min_size` and `frontend_max_size` in tfvars, through a PR.
- **Scale-in is disabled** (`allow_scale_in = false`), because a removed front-end must also be disabled in Service Center → Administration → Servers. To remove one manually:
  1. Disable the server in Service Center.
  2. Run `aws autoscaling set-desired-capacity` (or detach the instance).
  3. Terminate it.
- **Turn on automatic scale-in** only after adding a termination lifecycle hook that deregisters the server.
- **Vertical scaling:** change `frontend_instance_type`; apply, then roll the group with an ASG *instance refresh*. Change `controller_instance_type` / `db_instance_class` during a maintenance window. Both cause downtime for that tier; RDS Multi-AZ fails over to minimise it.

### Patching

- **Windows:** the observability module runs a daily **scan-only** Patch Manager association. Compliance shows in Systems Manager → Patch Manager. To install patches:
  1. Pick a maintenance window. For prod, drain one front-end at a time: set it to standby in the ASG.
  2. Run `AWS-RunPatchBaseline` with `Operation=Install` against `tag:OutSystemsEnvironment=<name>`. Use a Run Command rate control of one instance at a time for the front-ends.
  3. Patch the controller last. Platform services restart, and publishing pauses while it is down.
  4. Confirm health in the CloudWatch dashboard and Service Center.
- **RDS:** minor versions auto-upgrade in `maintenance_window`. Major versions are a planned change: update `db_engine_version`, apply during a window, and check OutSystems compatibility first.
- **OutSystems Platform Server:** upgrade the controller first, then the front-ends (or bake a new golden AMI). Follow the OutSystems upgrade checklist. Take an on-demand AWS Backup of the controller and an RDS snapshot first.
- **Terraform providers:** run `make lock` after bumping versions, and review the plan for every environment.

### Golden AMI and instance replacement

1. Launch a front-end from the base AMI. Install the target Platform Server version and add `C:\ProgramData\OutSystemsBootstrap\setup.ps1`. It should:
   - read the secrets via the instance role;
   - write `server.hsconf` and `private.key`;
   - run the Configuration Tool silently;
   - wait for registration.
2. Generalise the instance with EC2Launch (sysprep) and create an AMI.
3. Set `frontend_ami_id` and `enable_launch_lifecycle_hook = true`, then apply.
4. Start an ASG **instance refresh** (minimum healthy 100% in prod) to replace the front-ends gradually.

The controller ignores AMI and user-data changes by design. Replace it only through the restore runbook.

### Backup and restore

| What | How | Retention |
|---|---|---|
| Platform databases | RDS automated backups with point-in-time recovery (~5 min RPO) | `db_backup_retention_days` |
| Database + controller | AWS Backup daily, selected by tag `BackupPlan=<name>` | `backup_retention_days` |
| Cross-region | AWS Backup copy to `dr_region` (prod, lifetime) | `dr_backup_retention_days` |
| Front-ends | Not backed up: stateless, rebuilt from the AMI and redeployed by the controller | — |
| Terraform state | S3 versioning (90 days of previous versions) | — |

**On-demand backup** (before upgrades): AWS Backup → *Create on-demand backup*, or:

```bash
aws backup start-backup-job --backup-vault-name os11-prod --resource-arn <arn> --iam-role-arn <backup role arn>
```

**Restore the database** (corruption or a bad deployment):

1. Restore RDS to a point in time as a **new** instance.
2. Either update the database host in the Configuration Tool on every server, or swap the instances: rename the old one, then rename the restored one to the original identifier.
3. Import the restored instance into state if it replaced the managed one (`terraform import`), or re-plan to confirm there's no drift.

**Restore the controller:**

1. Restore the latest controller recovery point from AWS Backup into the same subnet and security group, with the same private IP if possible.
2. Update state: `terraform state rm module.platform.aws_instance.controller` then `terraform import ...`.
3. Front-ends reconnect once the controller answers on the registered address.

**Restore Terraform state:** recover the previous object version in the state bucket, then run `terraform plan` and check there is no unexpected drift.

Test restores at least quarterly in a non-prod environment.

### Disaster recovery (region loss)

The DR posture is **backup and restore**: RPO is about 24 hours for EBS and AWS Backup snapshots; RTO is hours.

1. Create `envs/prod-dr/` from `envs/prod/` with:
   - `region` set to the DR region;
   - a new state key (`outsystems/prod-dr/...`);
   - a non-overlapping `vpc_cidr`;
   - a different `name_prefix` (e.g. `os11dr`), because IAM role names are global and would collide with prod's.

   Add `prod-dr` to `scripts/tf.ps1`'s `ValidateSet` if you use PowerShell.
2. Apply it, and remove or stop the empty controller and RDS instance it creates.
3. Restore the RDS and controller recovery points from the `<name>-dr` vault into the new VPC. Re-import them into the DR state.
4. Re-run the Configuration Tool on the restored controller if the database host changed. Redeploy the front-ends (the ASG plus the controller's deployment).
5. Switch DNS to the DR ALB. Re-register the environment in LifeTime if its URL changed.

Rehearse this at least yearly. A warm standby (a second live stack plus database replication) would need further work.

### Secret rotation

| Secret | Rotation |
|---|---|
| RDS master (`database_master_secret_arn`) | Rotated automatically by RDS. To rotate now: `aws rds modify-db-instance --db-instance-identifier <id> --rotate-master-user-password --apply-immediately` (or the console). OutSystems doesn't use it at runtime. |
| `db-admin` / `db-runtime` / `db-log` / `db-session` | 1. Put the new value in Secrets Manager. 2. Change the database login password with `ALTER LOGIN`, using the master user. 3. Update the Configuration Tool on the **controller and every front-end** in a maintenance window, then Apply. 4. Golden-AMI `setup.ps1` reads the new value automatically. |
| `rabbitmq` | 1. Change the RabbitMQ user on the controller. 2. Update the secret. 3. Update the Cache Invalidation settings in the Configuration Tool on every server. |
| `platform-admin` | Change the password in Service Center, then update the secret. |
| `private.key` | Rotating it requires re-encrypting the platform configuration. Follow the OutSystems procedure; never edit it piecemeal. |
| CI | Nothing to rotate. GitHub OIDC issues short-lived credentials per job. |

### Certificate renewal

- **ACM-issued certificates** (`domain_name` + `route53_zone_id`) renew automatically while the DNS validation record exists. Don't delete it.
- **Imported certificates** (`certificate_arn`): import the renewed certificate under the **same ARN** with `aws acm import-certificate --certificate-arn ...`, before it expires.

### Monitoring and alerts

- **CloudWatch dashboard** `<prefix>-<env>` shows requests, errors, latency, healthy hosts, CPU and database load.
- **Alarms** go to the `alarm_topic_arn` SNS topic. Subscribe more endpoints (PagerDuty, Slack via Chatbot) outside Terraform, or through `alarm_emails`.

| Alarm | First response |
|---|---|
| `alb-5xx` / `unhealthy-hosts` | Check target health in EC2 → Target Groups, then IIS and Platform Server logs in `/outsystems/<env>/...`. |
| `target-5xx` | Application errors: check Service Center → Monitoring → Errors. |
| `controller-*` | The controller self-recovers on hardware faults. For a status-check, CPU or disk alarm, connect with Session Manager. |
| `db-cpu` / `db-storage` | Check Performance Insights or slow queries. Storage autoscales up to `db_max_allocated_storage_gb`. |

- **Logs:**
  - Windows events, IIS and Platform Server service logs: CloudWatch Logs.
  - OutSystems application logs: the platform log database (Service Center).
  - ALB access logs: S3.
  - VPC flow logs and WAF logs: CloudWatch Logs.

## Destroying an environment

1. For prod and LifeTime, set `termination_protection = false` and `db_deletion_protection = false`, then apply.
   - The guardrails will refuse this while `environment = "prod"`. That's intentional: destroying prod requires changing the guardrails in a reviewed PR.
2. Plan and apply the destroy:

```bash
make plan-destroy ENV=dev
scripts/tf.sh dev apply dev-destroy.tfplan
```

What happens to data:

- RDS takes a final snapshot unless deletion protection was off.
- Backup vaults that still hold recovery points block deletion unless `termination_protection = false`.
- KMS keys enter a 30-day deletion window.
- Secrets enter their recovery window.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Error: AccessDenied ... allowed_account_ids` / *"account ID not allowed"* | Your credentials point at the wrong account. Check `aws sts get-caller-identity` and the `allowed_account_ids` in tfvars. |
| `backend.hcl key does not point at outsystems/<env>/` | The wrapper caught a backend/tfvars mismatch. Fix `envs/<env>/backend.hcl`. |
| `Backend configuration changed` after switching env | You ran Terraform directly in `stack/`. Use `make` or `scripts/tf.sh`, which keep `.terraform-<env>` separate. |
| State lock stuck (`Error acquiring the state lock`) | Confirm no other run is active, then run `scripts/tf.sh <env> force-unlock <LOCK_ID>`. |
| `the given lock file ... does not match` in CI | A provider version changed without updating the lock files. Run `make lock` and commit. |
| KMS `MalformedPolicyDocument` mentioning `AWSServiceRoleForAutoScaling` | The service-linked role doesn't exist yet. Apply bootstrap with `create_autoscaling_service_linked_role = true`. |
| ASG instances fail with `Client.InvalidKMSKey.InvalidState` | Same cause: the Auto Scaling role can't use the key. Check that the role exists, then re-apply the security module. |
| ACM certificate stuck in *Pending validation* | The zone in `route53_zone_id` is not authoritative for `domain_name`, or the public delegation is missing. |
| Targets unhealthy right after deploy | Expected until OutSystems is installed and IIS answers on the target port. Check `health_check_path` and the IIS certificate binding (HTTPS targets). |
| New front-ends never become healthy | No golden AMI, or `setup.ps1` failed. Read `C:\ProgramData\OutSystemsBootstrap\bootstrap.log` via Session Manager. With the lifecycle hook on, failed instances are abandoned after `lifecycle_hook_timeout`. |
| Solution / module upload to Service Center returns 403 | The WAF blocks large bodies. Check that `SizeRestrictions_BODY` is still in `common_rule_overrides`, and review WAF logs in `aws-waf-logs-<name>`. |
| Session Manager can't connect | The instance lacks a route to the SSM endpoints or NAT, or the SSM agent is stopped. Check the VPC endpoints and the instance role. |
| `terraform test` fails with *unknown provider* | The module isn't initialised. Run `terraform -chdir=<dir> init -backend=false` (`scripts/test.sh` does this). |
| Checkov fails on a new resource | Fix it, or add a justified inline `#checkov:skip=<ID>:<reason>`. |
| Plan wants to replace the controller | Inspect the diff. AMI and user-data changes are already ignored; subnet or instance-profile changes do replace it. Plan a maintenance window and back up first. |

## Contributing and versioning

**Workflow:**

1. Branch from `main`.
2. Change the code and add or adjust tests in the matching `tests/` folder.
3. Run `make check`; pre-commit runs the same hooks on commit.
4. Open a PR. CI validates and posts a plan per environment; reviewers read the plans, not just the diff.
5. Merge. The apply jobs wait for Environment approval, in the order dev → test → lifetime → prod.

**Conventions:**

- Name resources `<name_prefix>-<environment>[-<role>]`. Every resource gets the default tags `Application`, `Environment` and `ManagedBy`.
- Every variable has a `description` and a `type`, plus a `validation` where a bad value would only fail at apply time.
- Modules are environment-agnostic: no hard-coded environment names. Environment policy lives in `stack/guardrails.tf` and `envs/`.
- **Secrets never enter Terraform**, including variables, tfvars, outputs and user data. Pass ARNs instead.
- Commit lock files for roots only (`stack/`, `bootstrap/`).
- Run `make docs` after changing module variables or outputs; CI fails on stale docs.

**Versioning:** `infra/` follows [Semantic Versioning](https://semver.org/). Releases are Git tags `infra-vMAJOR.MINOR.PATCH`.

| Bump | When |
|---|---|
| MAJOR | A change that replaces or destroys stateful resources (VPC, RDS, controller), or renames or removes variables or outputs |
| MINOR | New, backwards-compatible capabilities or variables with safe defaults |
| PATCH | Fixes, documentation and test changes with no infrastructure diff |

Record each release in [`CHANGELOG.md`](CHANGELOG.md), then tag it:

```bash
git tag -a infra-v1.1.0 -m "infra 1.1.0"
```

Pin the versions too:

- **Terraform:** `required_version` together with the CI `TF_VERSION`.
- **Providers:** `~> 6.0` in `stack/` and `bootstrap/`, plus the committed lock files.
- **Tools:** pinned in the workflow and in `.pre-commit-config.yaml`.

## Known limitations

- Terraform provisions the infrastructure only. The OutSystems install, licensing and LifeTime registration are the manual or AMI-driven steps above.
- Front-end scale-in and the golden-AMI `setup.ps1` are left for you to automate, because they depend on your OutSystems version and procedures.
- The controller is a single instance. It is recovered from backups, not clustered.
- ALB access logs use SSE-S3, because ALB log delivery doesn't support SSE-KMS.
- The IIS and Platform Server log paths in the CloudWatch agent config are the defaults. Adjust `modules/observability` if you install elsewhere.
- Cost drivers are licence-included RDS SQL Server (especially Multi-AZ), Windows EC2, NAT gateways, ALB, WAF and cross-region backup storage. Run the AWS Pricing Calculator against your tfvars first.
