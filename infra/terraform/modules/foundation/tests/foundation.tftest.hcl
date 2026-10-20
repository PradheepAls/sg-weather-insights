mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::114774131450:root" }
  }
}

variables {
  name = "sgw"
}

run "no_ci_roles_without_repository" {
  command = plan
  assert {
    condition     = length(aws_iam_role.ci_plan) == 0 && length(aws_iam_role.ci_apply) == 0
    error_message = "CI roles must not exist unless a repository is configured."
  }
  assert {
    condition     = aws_kms_key.this.enable_key_rotation
    error_message = "KMS key rotation must be enabled."
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.artifacts.block_public_acls,
      aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets,
      aws_s3_bucket_public_access_block.alb_logs.block_public_policy,
    ])
    error_message = "Buckets must block public access."
  }
}

run "apply_role_requires_github_environment" {
  command = plan
  variables {
    github_repository           = "example-org/sg-weather-insights"
    create_github_oidc_provider = false
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.ci_apply[0].assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]
      == "repo:example-org/sg-weather-insights:environment:*"
    )
    error_message = "Only jobs bound to a protected GitHub Environment may assume the apply role."
  }
}
