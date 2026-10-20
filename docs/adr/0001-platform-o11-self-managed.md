# ADR 0001 — OutSystems 11 self-managed on AWS

**Status:** Accepted

## Context
The brief asks for IaC that "defines the AWS infrastructure required to deploy and operate the
OutSystems Platforms". ODC is SaaS: its runtime cannot be provisioned on a customer's AWS
account, so IaC for ODC could only cover peripheral resources.

## Decision
Target OutSystems 11 on customer-managed AWS: LifeTime, Dev, Test and Prod environments, each
with its own RDS SQL Server instance and Windows Server 2022 application servers, provisioned
with Terraform.

## Consequences
* The IaC is the real platform footprint (network, compute, database, edge, observability),
  not a token exercise.
* We own patching, scaling and backups of the platform. Mitigated with SSM, ASG self-healing,
  RDS automated backups and Multi-AZ for Prod.
* The demo build runs on an OutSystems-hosted O11 environment (Personal Environment or trial
  factory) because standing up a licensed factory for an assessment is disproportionate. The
  application is platform-agnostic within O11, so the same OAP deploys unchanged to the
  Terraform-provisioned factory.
* If the organisation moves to ODC, the application layering (IS / CS / Lib / end-user) maps
  directly to ODC libraries and apps; the AWS IaC would shrink to private-gateway and
  observability resources.
