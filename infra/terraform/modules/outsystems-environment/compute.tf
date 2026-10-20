locals {
  bootstrap_key = "bootstrap/${var.environment}/bootstrap.ps1"

  bootstrap_vars = {
    environment             = var.environment
    is_lifetime             = local.is_lifetime
    platform_server_version = var.platform_server_version
    region                  = data.aws_region.current.region
    artifacts_bucket        = var.artifacts_bucket
    license_s3_key          = var.license_s3_key
    db_host                 = aws_db_instance.this.address
    db_force_ssl            = var.db_force_ssl
    platform_secret_arn     = aws_secretsmanager_secret.platform.arn
    private_key_secret_arn  = aws_secretsmanager_secret.private_key.arn
    master_secret_arn       = try(aws_db_instance.this.master_user_secret[0].secret_arn, "")
    controller_fqdn         = local.controller_fqdn
    catalog_platform        = local.catalogs.platform
    catalog_log             = local.catalogs.log
    catalog_session         = local.catalogs.session
  }

  # Tiny user-data stub: the full script lives in S3 (user data is capped at 16 KB) and holds
  # no secrets — it fetches them from Secrets Manager with the instance role.
  user_data = {
    for role in ["controller", "frontend"] : role => base64encode(<<-PS
      <powershell>
      $ErrorActionPreference = 'Stop'
      New-Item -ItemType Directory -Force -Path C:\ProgramData\sgw | Out-Null
      Read-S3Object -BucketName '${var.artifacts_bucket}' -Key '${local.bootstrap_key}' -File C:\ProgramData\sgw\bootstrap.ps1 -Region '${data.aws_region.current.region}'
      & C:\ProgramData\sgw\bootstrap.ps1 -Role '${role}'
      </powershell>
      <persist>false</persist>
      PS
    )
  }
}

data "aws_region" "current" {}

resource "aws_s3_object" "bootstrap" {
  bucket       = var.artifacts_bucket
  key          = local.bootstrap_key
  content      = templatefile("${path.module}/templates/bootstrap.ps1.tftpl", local.bootstrap_vars)
  content_type = "text/plain"
  kms_key_id   = var.kms_key_arn
  tags         = local.tags
}

resource "aws_launch_template" "server" {
  for_each = local.user_data

  name     = "${local.name}-${each.key}"
  image_id = "resolve:ssm:${var.ami_ssm_parameter}"
  instance_type = (each.key == "controller"
    ? var.controller_instance_type
  : var.frontend_instance_type)
  user_data              = each.value
  vpc_security_group_ids = [aws_security_group.server.id]
  update_default_version = true
  ebs_optimized          = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.server.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-${each.key}", Role = each.key })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-${each.key}" })
  }

  tags = local.tags
}

# The Deployment Controller is stateful (compiler cache, it is the farm's reference node), so it
# is a single named instance with auto-recovery, not part of the ASG.
resource "aws_instance" "controller" {
  subnet_id = var.app_subnet_ids[0]

  launch_template {
    id      = aws_launch_template.server["controller"].id
    version = aws_launch_template.server["controller"].latest_version
  }

  tags = merge(local.tags, { Name = "${local.name}-controller", Role = "controller" })

  depends_on = [aws_s3_object.bootstrap, aws_secretsmanager_secret_version.platform]

  lifecycle {
    # A new AMI or bootstrap revision must not silently replace the controller; replace it
    # deliberately with `terraform apply -replace=...` during a change window.
    ignore_changes = [launch_template]
  }
}

resource "aws_autoscaling_group" "frontend" {
  count = local.frontend_enabled ? 1 : 0

  name                      = "${local.name}-frontend"
  vpc_zone_identifier       = var.app_subnet_ids
  min_size                  = var.frontend_min
  max_size                  = var.frontend_max
  desired_capacity          = var.frontend_desired
  target_group_arns         = [aws_lb_target_group.servers.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 3600 # Platform Server install + configuration takes ~30-45 min
  default_instance_warmup   = 600
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.server["frontend"].id
    version = aws_launch_template.server["frontend"].latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 3600
    }
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${local.name}-frontend", Role = "frontend" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [aws_instance.controller]

  lifecycle {
    precondition {
      condition     = !var.is_production || (var.frontend_min >= 2 && var.dedicated_controller)
      error_message = "Production needs a dedicated controller and at least two front-ends across AZs."
    }
  }
}

resource "aws_autoscaling_policy" "frontend_cpu" {
  count                  = local.frontend_enabled ? 1 : 0
  name                   = "${local.name}-frontend-cpu"
  autoscaling_group_name = aws_autoscaling_group.frontend[0].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}
