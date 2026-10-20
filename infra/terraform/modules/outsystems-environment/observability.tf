locals {
  log_groups = {
    bootstrap  = "/${var.project}/${var.environment}/bootstrap"
    outsystems = "/${var.project}/${var.environment}/outsystems"
    iis        = "/${var.project}/${var.environment}/iis"
    windows    = "/${var.project}/${var.environment}/windows-events"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = local.log_groups
  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = local.tags
}

resource "aws_ssm_parameter" "cwagent" {
  name = "/${var.project}/${var.environment}/cloudwatch-agent"
  type = "String"
  value = templatefile("${path.module}/templates/cwagent.json.tftpl", {
    namespace      = "${var.project}/${var.environment}"
    log_bootstrap  = local.log_groups.bootstrap
    log_outsystems = local.log_groups.outsystems
    log_iis        = local.log_groups.iis
    log_windows    = local.log_groups.windows
  })
  tags = local.tags
}

# Agents are installed and configured by SSM State Manager, not baked into user data, so a
# config change rolls out to every server without rebuilding them.
resource "aws_ssm_association" "cwagent_install" {
  name             = "AWS-ConfigureAWSPackage"
  association_name = "${local.name}-cwagent-install"
  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }
  targets {
    key    = "tag:Environment"
    values = [var.environment]
  }
  targets {
    key    = "tag:Project"
    values = [var.project]
  }
}

resource "aws_ssm_association" "cwagent_configure" {
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "${local.name}-cwagent-configure"
  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cwagent.name
    optionalRestart               = "yes"
  }
  targets {
    key    = "tag:Environment"
    values = [var.environment]
  }
  targets {
    key    = "tag:Project"
    values = [var.project]
  }
  depends_on = [aws_ssm_association.cwagent_install]
}

resource "aws_ssm_association" "patch" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "${local.name}-patch"
  schedule_expression = "cron(0 18 ? * SAT *)" # Sunday 02:00 SGT
  parameters = {
    Operation    = var.patch_operation
    RebootOption = var.patch_operation == "Install" ? "RebootIfNeeded" : "NoReboot"
  }
  targets {
    key    = "tag:Environment"
    values = [var.environment]
  }
  targets {
    key    = "tag:Project"
    values = [var.project]
  }
}

# ---------------------------------------------------------------- alarms

locals {
  alb_dims = { LoadBalancer = aws_lb.this.arn_suffix }
  tg_dims  = { LoadBalancer = aws_lb.this.arn_suffix, TargetGroup = aws_lb_target_group.servers.arn_suffix }
  db_dims  = { DBInstanceIdentifier = aws_db_instance.this.identifier }

  alarms = {
    alb-5xx = {
      namespace = "AWS/ApplicationELB", metric = "HTTPCode_ELB_5XX_Count", stat = "Sum"
      threshold = 20, comparison = "GreaterThanThreshold", dims = local.alb_dims
      desc      = "Load balancer is returning 5xx (no healthy targets or overload)"
    }
    target-5xx = {
      namespace = "AWS/ApplicationELB", metric = "HTTPCode_Target_5XX_Count", stat = "Sum"
      threshold = 50, comparison = "GreaterThanThreshold", dims = local.alb_dims
      desc      = "OutSystems servers returning 5xx"
    }
    unhealthy-hosts = {
      namespace = "AWS/ApplicationELB", metric = "UnHealthyHostCount", stat = "Maximum"
      threshold = 0, comparison = "GreaterThanThreshold", dims = local.tg_dims
      desc      = "At least one server failing health checks"
    }
    latency-p95 = {
      namespace = "AWS/ApplicationELB", metric = "TargetResponseTime", stat = "p95"
      threshold = 2, comparison = "GreaterThanThreshold", dims = local.alb_dims
      desc      = "p95 response time above 2 s"
    }
    db-cpu = {
      namespace = "AWS/RDS", metric = "CPUUtilization", stat = "Average"
      threshold = 80, comparison = "GreaterThanThreshold", dims = local.db_dims
      desc      = "Database CPU above 80%"
    }
    db-storage = {
      namespace = "AWS/RDS", metric = "FreeStorageSpace", stat = "Minimum"
      threshold = var.db_allocated_storage_gb * 1073741824 * 0.1, comparison = "LessThanThreshold", dims = local.db_dims
      desc      = "Database free storage below 10% of allocated (autoscaling may be at max)"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.desc
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dims
  statistic           = startswith(each.value.stat, "p") ? null : each.value.stat
  extended_statistic  = startswith(each.value.stat, "p") ? each.value.stat : null
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "controller_recover" {
  alarm_name          = "${local.name}-controller-recover"
  alarm_description   = "Hardware failure: recover the controller onto healthy host (same IP, same volume)"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.controller.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.region}:ec2:recover", var.alarm_topic_arn]
  tags                = local.tags
}

# Application-level signal: no successful sync recently. Weather_CS logs a structured line on
# every SyncRun; this metric filter counts failures.
resource "aws_cloudwatch_log_metric_filter" "sync_failed" {
  count          = local.is_lifetime ? 0 : 1
  name           = "${local.name}-sync-failed"
  log_group_name = aws_cloudwatch_log_group.this["outsystems"].name
  pattern        = "\"SYNC_RUN\" \"status=Failed\""
  metric_transformation {
    name      = "SyncFailures"
    namespace = "${var.project}/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "sync_failed" {
  count               = local.is_lifetime ? 0 : 1
  alarm_name          = "${local.name}-sync-failed"
  alarm_description   = "data.gov.sg ingestion failing repeatedly (3+ failures in 15 min)"
  namespace           = "${var.project}/${var.environment}"
  metric_name         = "SyncFailures"
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  tags                = local.tags
}
