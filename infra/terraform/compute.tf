locals {
  bootstrap = {
    environment             = var.environment
    is_lifetime             = local.is_lifetime
    platform_server_version = var.platform_server_version
    region                  = var.region
    db_host                 = aws_db_instance.this.address
    master_secret_arn       = try(aws_db_instance.this.master_user_secret[0].secret_arn, "")
    platform_secret_arn     = aws_secretsmanager_secret.platform.arn
    private_key_secret_arn  = aws_secretsmanager_secret.private_key.arn
    license_bucket          = var.license_bucket
    license_key             = var.license_key
    catalog_platform        = local.catalogs.platform
    catalog_log             = local.catalogs.log
    catalog_session         = local.catalogs.session
  }
}

# Windows Server 2022, resolved from AWS's public SSM parameter at launch: new instances
# always start from the latest patched AMI without editing Terraform.
locals {
  ami = "resolve:ssm:/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

resource "aws_launch_template" "controller" {
  name                   = "${local.name}-controller"
  image_id               = local.ami
  instance_type          = var.controller_instance_type
  vpc_security_group_ids = [aws_security_group.server.id]
  ebs_optimized          = true
  user_data = base64encode(templatefile("${path.module}/templates/bootstrap.ps1.tftpl",
  merge(local.bootstrap, { role = "controller", controller_host = "" })))

  iam_instance_profile {
    arn = aws_iam_instance_profile.server.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 120
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_key.this.arn
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-controller", Role = "controller" }
  }
}

# The Deployment Controller is the farm's reference server (compiles and deploys apps),
# so it is a single named instance with automatic recovery rather than part of the ASG.
resource "aws_instance" "controller" {
  subnet_id = aws_subnet.private[0].id

  launch_template {
    id      = aws_launch_template.controller.id
    version = aws_launch_template.controller.latest_version
  }

  tags = { Name = "${local.name}-controller", Role = "controller" }

  lifecycle {
    # Never replace the controller by accident (new AMI, edited bootstrap). Replace it on
    # purpose with: terraform apply -replace=aws_instance.controller
    ignore_changes = [launch_template]
  }
}

resource "aws_launch_template" "frontend" {
  count                  = local.has_farm ? 1 : 0
  name                   = "${local.name}-frontend"
  image_id               = local.ami
  instance_type          = var.frontend_instance_type
  vpc_security_group_ids = [aws_security_group.server.id]
  ebs_optimized          = true
  user_data = base64encode(templatefile("${path.module}/templates/bootstrap.ps1.tftpl",
  merge(local.bootstrap, { role = "frontend", controller_host = aws_instance.controller.private_ip })))

  iam_instance_profile {
    arn = aws_iam_instance_profile.server.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 120
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_key.this.arn
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-frontend", Role = "frontend" }
  }
}

# Front-end farm across both AZs; replaced automatically if a server fails health checks.
resource "aws_autoscaling_group" "frontend" {
  count                     = local.has_farm ? 1 : 0
  name                      = "${local.name}-frontend"
  vpc_zone_identifier       = aws_subnet.private[*].id
  min_size                  = var.frontend_count
  max_size                  = var.frontend_count * 2
  desired_capacity          = var.frontend_count
  target_group_arns         = [aws_lb_target_group.servers.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 3600 # platform install + configuration takes 30-45 minutes

  launch_template {
    id      = aws_launch_template.frontend[0].id
    version = aws_launch_template.frontend[0].latest_version
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-frontend"
    propagate_at_launch = true
  }

  lifecycle {
    precondition {
      condition     = !var.is_production || var.frontend_count >= 2
      error_message = "Production needs at least two front-end servers across two AZs."
    }
  }
}
