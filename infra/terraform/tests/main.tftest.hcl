# Runs offline with a mocked AWS provider (no credentials, nothing created).
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }

  # The provider validates ARN/ID formats even for mocked values, so give the resources
  # that feed other resources realistic identifiers.
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:ap-southeast-1:111122223333:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:ap-southeast-1:111122223333:sgw-alarms" }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:111122223333:loadbalancer/app/sgw/0123456789abcdef"
      arn_suffix = "app/sgw/0123456789abcdef"
      dns_name   = "sgw-123.ap-southeast-1.elb.amazonaws.com"
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
    defaults = { arn = "arn:aws:iam::111122223333:role/sgw-server" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111122223333:instance-profile/sgw-server" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:ap-southeast-1:111122223333:secret:sgw-AbCdEf" }
  }
  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      arn            = "arn:aws:ec2:ap-southeast-1:111122223333:launch-template/lt-0123456789abcdef0"
      latest_version = 1
    }
  }
  mock_resource "aws_instance" {
    defaults = {
      id         = "i-0123456789abcdef0"
      private_ip = "10.20.128.10"
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      arn     = "arn:aws:rds:ap-southeast-1:111122223333:db:sgw-dev"
      address = "sgw-dev.abc123.ap-southeast-1.rds.amazonaws.com"
    }
  }
}

variables {
  environment             = "dev"
  alb_ingress_cidrs       = ["10.0.0.0/8"]
  admin_cidrs             = ["10.99.0.0/16"]
  certificate_arn         = "arn:aws:acm:ap-southeast-1:111122223333:certificate/test"
  platform_server_version = "11.31.0"
  license_bucket          = "sgw-licences"
  license_key             = "licenses/dev.lic"
}

run "dev_is_secure_by_default" {
  command = apply # mocked: lets us assert on rendered values such as user data

  assert {
    condition     = aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible
    error_message = "Database must be encrypted and private."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "RDS must manage the master password (no password in state)."
  }
  assert {
    condition     = aws_launch_template.controller.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced."
  }
  assert {
    condition     = aws_launch_template.controller.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Server disks must be encrypted."
  }
  assert {
    condition     = alltrue([for r in aws_security_group.db.ingress : r.from_port == 1433 && length(r.cidr_blocks) == 0])
    error_message = "SQL Server must only be reachable from the server security group."
  }
  assert {
    condition     = alltrue([for r in aws_security_group.server.ingress : !(r.from_port <= 3389 && r.to_port >= 3389) && !(r.from_port <= 22 && r.to_port >= 22)])
    error_message = "No RDP/SSH ingress; use SSM Session Manager."
  }
  assert {
    condition     = aws_lb_listener_rule.admin_deny.action[0].fixed_response[0].status_code == "403"
    error_message = "Service Center / LifeTime must be blocked for non-admin networks."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.controller) == 1 && length(aws_autoscaling_group.frontend) == 0
    error_message = "Without a farm, the controller serves traffic and no ASG is created."
  }
  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.controller.user_data), "Install-OSServer -Version '11.31.0'")
      && strcontains(base64decode(aws_launch_template.controller.user_data), "Get-SECSecretValue")
    )
    error_message = "Bootstrap must install the pinned version and read credentials from Secrets Manager."
  }
  assert {
    condition     = length(base64decode(aws_launch_template.controller.user_data)) < 16000
    error_message = "User data must stay under the 16 KB EC2 limit."
  }
}

run "production_shape" {
  command = apply
  variables {
    environment              = "prod"
    is_production            = true
    alb_internal             = false
    alb_ingress_cidrs        = ["0.0.0.0/0"]
    frontend_count           = 2
    db_multi_az              = true
    deletion_protection      = true
    db_backup_retention_days = 35
  }
  assert {
    condition     = aws_autoscaling_group.frontend[0].min_size == 2 && length(aws_autoscaling_group.frontend[0].vpc_zone_identifier) == 2
    error_message = "Prod runs two front-ends across two AZs."
  }
  assert {
    condition     = length(aws_lb_target_group_attachment.controller) == 0
    error_message = "Prod controller must not serve user traffic."
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.frontend[0].user_data), "10.20.128.10")
    error_message = "Front-ends must point at the controller."
  }
  assert {
    condition     = aws_db_instance.this.multi_az && !aws_db_instance.this.skip_final_snapshot && aws_lb.this.enable_deletion_protection
    error_message = "Prod DB must be Multi-AZ with a final snapshot, and the ALB protected."
  }
}

run "prod_rejects_single_az_database" {
  command = plan
  variables {
    environment         = "prod"
    is_production       = true
    frontend_count      = 2
    deletion_protection = true
    db_multi_az         = false
  }
  expect_failures = [aws_db_instance.this]
}

run "prod_rejects_single_front_end" {
  command = plan
  variables {
    environment              = "prod"
    is_production            = true
    frontend_count           = 1
    db_multi_az              = true
    deletion_protection      = true
    db_backup_retention_days = 35
  }
  expect_failures = [aws_autoscaling_group.frontend]
}

run "rejects_unpinned_platform_version" {
  command = plan
  variables {
    platform_server_version = "latest"
  }
  expect_failures = [var.platform_server_version]
}
