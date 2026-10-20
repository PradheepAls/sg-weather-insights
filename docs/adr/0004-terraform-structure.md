# ADR 0004 — Terraform structure, state and secrets

**Status:** Accepted

## Decision
* Reusable modules: `foundation` (KMS, buckets, SNS, CI role), `network` (VPC),
  `outsystems-environment` (one OutSystems environment).
* Two stacks: `foundation` (applied once) and `environment` (applied per environment with its
  own var file and state key). Separate states limit blast radius: a bad Dev apply cannot touch
  Prod.
* S3 backend with native lockfile (`use_lockfile`, Terraform ≥ 1.10), no DynamoDB table.
* Secrets are generated as ephemeral values and written with write-only arguments
  (`secret_string_wo`, Terraform ≥ 1.11), so platform passwords never land in state. The RDS
  master password is managed by RDS in Secrets Manager.
* CI authenticates to AWS with GitHub OIDC, no long-lived keys.

## Alternatives
* Terragrunt — less boilerplate, but another tool for reviewers to learn; plain Terraform with
  var files is enough at four environments.
* Workspaces — hide which environment a plan targets; explicit var files and state keys are
  easier to review.
