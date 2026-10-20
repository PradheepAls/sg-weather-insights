# CI identities for GitHub Actions. Two roles: read-only "plan" for pull requests and "apply"
# restricted to the main branch / protected environments. No long-lived AWS keys in GitHub.

locals {
  ci_enabled = var.github_repository != ""
  oidc_arn = local.ci_enabled ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
  ) : ""
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.ci_enabled && var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

resource "aws_iam_role" "ci_plan" {
  count = local.ci_enabled ? 1 : 0
  name  = "${var.name}-ci-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*" }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ci_plan_readonly" {
  count      = local.ci_enabled ? 1 : 0
  role       = aws_iam_role.ci_plan[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role" "ci_apply" {
  count = local.ci_enabled ? 1 : 0
  name  = "${var.name}-ci-apply"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        # Only jobs bound to a GitHub Environment (which carries required reviewers) can apply.
        StringLike = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:*" }
      }
    }]
  })
  tags = var.tags
}

# Broad by necessity (Terraform manages VPC, EC2, RDS, IAM roles). Scope is limited by the
# trust policy above and by a permissions boundary in a hardened account setup.
resource "aws_iam_role_policy_attachment" "ci_apply_admin" {
  count      = local.ci_enabled ? 1 : 0
  role       = aws_iam_role.ci_apply[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "ci_apply_iam" {
  count = local.ci_enabled ? 1 : 0
  name  = "manage-project-iam"
  role  = aws_iam_role.ci_apply[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["iam:*Role*", "iam:*InstanceProfile*", "iam:*Policy*", "iam:PassRole", "iam:*OpenIDConnectProvider*", "iam:CreateServiceLinkedRole"]
      Resource = [
        "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*",
        "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.name}-*",
        "arn:${local.partition}:iam::${local.account_id}:policy/${var.name}-*",
        "arn:${local.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com",
        "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*",
      ]
    }]
  })
}
