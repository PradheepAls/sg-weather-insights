# Tests with a mocked AWS provider: no credentials, no cost, run on every push.
# `apply` runs use mock values for computed attributes (so rendered bootstrap content can be
# asserted); guard-rail runs use `plan` + expect_failures. The random provider is real (local).

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ap-southeast-1" }
  }

  # The provider validates ARN-typed arguments even with mocked values, so give every
  # resource whose ARN feeds another resource a well-formed one.
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:loadbalancer/app/sgw/0123456789abcdef"
      arn_suffix = "app/sgw/0123456789abcdef"
      dns_name   = "internal-sgw-123.ap-southeast-1.elb.amazonaws.com"
      zone_id    = "Z1LMS91P8CMLE5"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:targetgroup/sgw/0123456789abcdef"
      arn_suffix = "targetgroup/sgw/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:listener/app/sgw/0123456789abcdef/0123456789abcdef" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/sgw-mock" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111122223333:instance-profile/sgw-mock" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:ap-southeast-1:111122223333:secret:sgw-mock-AbCdEf" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:ap-southeast-1:111122223333:regional/webacl/sgw/0123-4567" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:ap-southeast-1:111122223333:log-group:mock" }
  }
  mock_resource "aws_ssm_parameter" {
    defaults = { arn = "arn:aws:ssm:ap-southeast-1:111122223333:parameter/mock" }
  }
  mock_resource "aws_instance" {
    defaults = {
      id         = "i-0123456789abcdef0"
      private_ip = "10.20.128.10"
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      arn        = "arn:aws:rds:ap-southeast-1:111122223333:db:sgw-mock"
      address    = "sgw-mock.abc123.ap-southeast-1.rds.amazonaws.com"
      identifier = "sgw-mock"
    }
  }
}

variables {
  project                 = "sgw"
  environment             = "dev"
  vpc_id                  = "vpc-0123456789abcdef0"
  public_subnet_ids       = ["subnet-pub-a", "subnet-pub-b"]
  app_subnet_ids          = ["subnet-app-a", "subnet-app-b"]
  data_subnet_ids         = ["subnet-data-a", "subnet-data-b"]
  lifetime_cidr           = "10.20.0.0/16"
  alb_ingress_cidrs       = ["10.20.0.0/16"]
  admin_cidrs             = ["10.99.0.0/16"]
  kms_key_arn             = "arn:aws:kms:ap-southeast-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  artifacts_bucket        = "sgw-artifacts-111122223333"
  alb_logs_bucket         = "sgw-alb-logs-111122223333"
  alarm_topic_arn         = "arn:aws:sns:ap-southeast-1:111122223333:sgw-alarms"
  certificate_arn         = "arn:aws:acm:ap-southeast-1:111122223333:certificate/test"
  public_hostname         = "weather-dev.example.gov.sg"
  private_zone_id         = "Z0PRIVATE"
  private_zone_name       = "sgw.internal"
  platform_server_version = "11.31.0"
  license_s3_key          = "licenses/dev.lic"
}

run "dev_baseline_is_secure_by_default" {
  command = apply

  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible
    error_message = "Database must be encrypted and private."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "RDS must own the master password (no password in state)."
  }
  assert {
    condition     = alltrue([for lt in aws_launch_template.server : lt.metadata_options[0].http_tokens == "required"])
    error_message = "IMDSv2 must be enforced on every server."
  }
  assert {
    condition     = alltrue([for lt in aws_launch_template.server : lt.block_device_mappings[0].ebs[0].encrypted == "true"])
    error_message = "Root volumes must be encrypted."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_servers.from_port == 1433 && aws_vpc_security_group_ingress_rule.db_from_servers.cidr_ipv4 == null
    error_message = "SQL Server must only be reachable from the server security group, never a CIDR."
  }
  assert {
    condition     = alltrue([for r in values(aws_vpc_security_group_ingress_rule.server_internal) : !(r.from_port <= 3389 && r.to_port >= 3389) && !(r.from_port <= 22 && r.to_port >= 22)])
    error_message = "No RDP/SSH ingress; use SSM Session Manager."
  }
  assert {
    condition     = aws_lb.this.internal && aws_lb.this.drop_invalid_header_fields
    error_message = "Dev ALB must be internal and drop invalid headers."
  }
  assert {
    condition     = aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener must use the TLS 1.2+/1.3 policy."
  }
  assert {
    condition     = aws_lb_listener_rule.admin_deny.action[0].fixed_response[0].status_code == "403"
    error_message = "Service Center / LifeTime paths must be denied by default."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.controller) == 1
    error_message = "In Dev the controller doubles as front-end and must be in the target group."
  }
  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0
    error_message = "WAF is opt-in outside Prod."
  }
  assert {
    condition     = strcontains(aws_s3_object.bootstrap.content, "Install-OSServer -Version $PlatformVersion") && strcontains(aws_s3_object.bootstrap.content, "Get-SECSecretValue")
    error_message = "Bootstrap must install the pinned version and read credentials from Secrets Manager at run time."
  }
}

run "production_shape" {
  command = apply

  variables {
    environment              = "prod"
    is_production            = true
    alb_internal             = false
    alb_ingress_cidrs        = ["0.0.0.0/0"]
    dedicated_controller     = true
    frontend_min             = 2
    frontend_max             = 6
    frontend_desired         = 2
    db_multi_az              = true
    deletion_protection      = true
    db_backup_retention_days = 35
    enable_waf               = true
    patch_operation          = "Scan"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1 && length(aws_wafv2_web_acl_association.this) == 1
    error_message = "Prod must be fronted by WAF."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.controller) == 0
    error_message = "Prod controller must not serve end-user traffic."
  }
  assert {
    condition     = aws_autoscaling_group.frontend[0].min_size >= 2 && length(aws_autoscaling_group.frontend[0].vpc_zone_identifier) >= 2
    error_message = "Prod needs at least two front-ends spread over two AZs."
  }
  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot
    error_message = "Prod DB must be Multi-AZ, protected and keep a final snapshot."
  }
  assert {
    condition     = aws_lb.this.enable_deletion_protection
    error_message = "Prod ALB must have deletion protection."
  }
}

run "production_rejects_single_az_database" {
  command = plan
  variables {
    environment          = "prod"
    is_production        = true
    dedicated_controller = true
    frontend_min         = 2
    frontend_desired     = 2
    deletion_protection  = true
    db_multi_az          = false
  }
  expect_failures = [aws_db_instance.this]
}

run "production_rejects_single_front_end" {
  command = plan
  variables {
    environment              = "prod"
    is_production            = true
    dedicated_controller     = true
    frontend_min             = 1
    frontend_desired         = 1
    db_multi_az              = true
    deletion_protection      = true
    db_backup_retention_days = 35
  }
  expect_failures = [aws_autoscaling_group.frontend]
}

run "lifetime_is_a_single_server" {
  command = apply
  variables {
    environment  = "lifetime"
    frontend_max = 2
  }
  assert {
    condition     = length(aws_autoscaling_group.frontend) == 0
    error_message = "LifeTime must not create a front-end farm."
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.server_from_lifetime) == 0
    error_message = "LifeTime does not need an ingress rule from itself."
  }
  assert {
    condition     = strcontains(aws_s3_object.bootstrap.content, "[bool]::Parse('true')")
    error_message = "Bootstrap must install LifeTime on the LifeTime environment."
  }
}

run "rejects_unknown_environment" {
  command = plan
  variables {
    environment = "staging"
  }
  expect_failures = [var.environment]
}

run "rejects_unpinned_platform_version" {
  command = plan
  variables {
    platform_server_version = "latest"
  }
  expect_failures = [var.platform_server_version]
}
