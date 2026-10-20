# Infrastructure (Terraform) — OutSystems 11 factory on AWS

Provisions a four-environment OutSystems 11 factory (LifeTime, Dev, Test, Prod) in
`ap-southeast-1`.

## Layout

```
bootstrap/                       state bucket (run once, local state)
modules/
  foundation/                    KMS CMK, artifacts + ALB-log buckets, SNS alarms, GitHub OIDC CI roles
  network/                       VPC, 3 tiers x 2 AZ, NAT, VPC endpoints, flow logs
  outsystems-environment/        one OutSystems environment (below)
stacks/
  foundation/                    foundation + nonprod VPC + prod VPC + peering + private zone
  environment/                   one state per environment, selected by envs/<env>.tfvars
```

## What one `outsystems-environment` creates

| Concern | Resources | Notes |
|---|---|---|
| Database | RDS SQL Server SE 2022, gp3, KMS, Performance Insights, enhanced monitoring, parameter group with `rds.force_ssl` | Three catalogs per environment (platform, log, session) created by bootstrap. Master password managed by RDS; OutSystems uses five least-privilege logins. Prod: Multi-AZ, 35-day backups, deletion protection, final snapshot (enforced by preconditions). |
| Servers | Launch templates (Windows Server 2022 via `resolve:ssm:`, IMDSv2, encrypted gp3), Deployment Controller instance with EC2 auto-recovery, front-end ASG with target tracking and rolling instance refresh | Non-prod controller doubles as front-end; Prod controller is dedicated and out of the target group. |
| Bootstrap | Script in S3 rendered from `templates/bootstrap.ps1.tftpl`, user-data stub | Installs prerequisites + pinned Platform Server via `Outsystems.SetupTools`, creates DB catalogs/logins, configures platform/log/session DBs and the cache invalidation service, shares `private.key` from controller to front-ends through Secrets Manager, installs licence (and LifeTime on the LifeTime env). Idempotent marker file; transcript shipped to CloudWatch. |
| Secrets | Secrets Manager (KMS) for DB logins + RabbitMQ, separate secret for `private.key` | Generated with **ephemeral** `random_password` and written via `secret_string_wo` — never in state. |
| Edge | ALB (internal for LifeTime/Dev/Test, public for Prod), HTTP→HTTPS, TLS 1.2/1.3 policy, end-to-end TLS, access logs, admin-path allow/deny rules, WAFv2 (IP reputation, common, bad inputs, SQLi, rate limit) on Prod | `/ServiceCenter*`, `/LifeTime*`, `/CI_CDProbe*`, `/BDDFramework*`, `/ServiceManager*` return 403 unless the source is an admin CIDR. |
| Access | SSM Session Manager only; no RDP/SSH rules, no bastion | VPC endpoints let servers reach SSM/Secrets Manager/Logs privately. |
| Observability | CloudWatch agent installed/configured by SSM State Manager, log groups (bootstrap, OutSystems, IIS, Windows events), alarms (ALB 5xx, target 5xx, unhealthy hosts, p95 latency, RDS CPU, RDS storage, controller recovery, ingestion failures) → SNS | `SyncFailures` comes from a metric filter on the app's `SYNC_RUN status=Failed` log line. |
| Patching | `AWS-RunPatchBaseline` weekly: Install in non-prod, Scan in Prod (patched in change windows) | |
| DNS | Public alias record (optional), private `controller.<env>.sgw.internal` | LifeTime registers environments by the private name, which survives instance replacement. |

## Prerequisites

* Terraform ≥ 1.11, AWS credentials for the target account.
* ACM certificates for each hostname.
* OutSystems licence files uploaded to `s3://<artifacts-bucket>/licenses/<env>.lic` (from the
  OutSystems customer portal).
* Network path for developers/admins to the internal ALBs (VPN or Direct Connect) matching
  `admin_cidrs`.

## Apply order

```bash
cd infra/terraform

# 1. state bucket (once)
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply
cp backend.hcl.example backend.hcl          # set the bucket name output above

# 2. foundation
terraform -chdir=stacks/foundation init -backend-config=../../backend.hcl -backend-config="key=foundation.tfstate"
terraform -chdir=stacks/foundation apply -var-file=terraform.tfvars

# 3. upload licences to the artifacts bucket, then each environment (LifeTime first)
for env in lifetime dev test prod; do
  terraform -chdir=stacks/environment init -reconfigure \
    -backend-config=../../backend.hcl -backend-config="key=env/${env}.tfstate"
  terraform -chdir=stacks/environment apply \
    -var-file=envs/${env}.tfvars -var="state_bucket=<bucket>"
done
```

`make tf-plan ENV=dev` wraps the same commands.

## After apply (one-off platform steps)

1. Watch `/sgw/<env>/bootstrap` in CloudWatch until "Bootstrap completed" (≈ 40 min).
2. Open Service Center on each environment and change the default admin password; store it
   in Secrets Manager under `sgw-<env>/outsystems/admin-console`.
3. In LifeTime, register Dev, Test and Prod using the `controller_fqdn` outputs.
4. Factory Configuration: enforce HTTPS, enable HSTS, set secure cookies.
5. Switch `health_check_path` to the app's health endpoint once the app is deployed (keeps
   instances out of rotation if the platform is up but the app is broken).

## Operations runbook

| Situation | Action |
|---|---|
| Patch / new AMI for front-ends | Update nothing — launch template resolves the latest AMI; start an ASG instance refresh. |
| Replace the controller | `terraform apply -replace=module.environment.aws_instance.controller` in a change window. The private DNS record follows; front-ends re-register on next restart. |
| Scale Prod | Change `frontend_*` in `envs/prod.tfvars` or let target tracking handle CPU. |
| Rotate DB login passwords | Bump `local.secret_version` in `secrets.tf`, apply, then re-run the configuration section of the bootstrap on each server (SSM Run Command). |
| Upgrade Platform Server | Change `platform_server_version`, apply, run the upgrade in Dev → Test → Prod with the Configuration Tool (OutSystems upgrades are not hot-swappable through Terraform). |
| Restore DB | Point-in-time restore from RDS automated backups to a new instance, then update `db_host` in `server.hsconf` (or import the restored instance into state). |

## Testing

```bash
make tf-test     # fmt -check, validate, terraform test (mocked AWS), tflint, checkov
```

`terraform test` runs entirely offline against a mocked AWS provider and asserts the
guard-rails: encryption everywhere, no public DB, IMDSv2, no RDP/SSH, admin paths denied,
Prod has WAF + Multi-AZ + ≥ 2 front-ends + dedicated controller (and that plans *fail* when
Prod violates them), LifeTime is a single server, versions are pinned, CI apply role is
restricted to protected GitHub Environments.

## Cost levers

The dominant costs are SQL Server licence-included RDS instances and Windows EC2 hours.
Options, in order of impact: share one RDS instance between Dev and Test (separate catalogs;
the module would take an external `db_host`), schedule non-prod instances off out of hours
(SSM Quick Setup scheduler), Savings Plans for Prod, and smaller Test front-ends. These were
not applied by default because isolation per environment is the safer starting point.

## Known assumptions

* `Outsystems.SetupTools` cmdlet names and `server.hsconf` section/setting names follow the
  module's 3.x documentation; verify against the pinned module and the
  `SqlServer_template.hsconf` generated on first install before production use.
* Inter-server ports 12000–12004 and 5672 follow the OutSystems 11 network requirements;
  confirm against the network requirements page for your Platform Server version.
* Amazon MQ (managed RabbitMQ) is a possible replacement for the controller-hosted RabbitMQ;
  not used because it is not a configuration OutSystems documents as supported.
