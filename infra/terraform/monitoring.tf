resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = aws_kms_key.this.id
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarms = {
    unhealthy-servers = {
      namespace = "AWS/ApplicationELB", metric = "UnHealthyHostCount", stat = "Maximum", threshold = 0
      dims      = { LoadBalancer = aws_lb.this.arn_suffix, TargetGroup = aws_lb_target_group.servers.arn_suffix }
      desc      = "A server is failing health checks", comparison = "GreaterThanThreshold"
    }
    server-5xx = {
      namespace = "AWS/ApplicationELB", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", threshold = 50
      dims      = { LoadBalancer = aws_lb.this.arn_suffix }
      desc      = "Servers returning many 5xx errors", comparison = "GreaterThanThreshold"
    }
    db-cpu = {
      namespace = "AWS/RDS", metric = "CPUUtilization", stat = "Average", threshold = 80
      dims      = { DBInstanceIdentifier = aws_db_instance.this.identifier }
      desc      = "Database CPU above 80%", comparison = "GreaterThanThreshold"
    }
    db-storage = {
      namespace = "AWS/RDS", metric = "FreeStorageSpace", stat = "Minimum", threshold = 10 * 1073741824
      dims      = { DBInstanceIdentifier = aws_db_instance.this.identifier }
      desc      = "Database free storage below 10 GB", comparison = "LessThanThreshold"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.desc
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dims
  statistic           = each.value.stat
  period              = 300
  evaluation_periods  = 2
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# Hardware failure on the controller: AWS moves it to a healthy host (same IP, same disk).
resource "aws_cloudwatch_metric_alarm" "controller_recover" {
  alarm_name          = "${local.name}-controller-recover"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.controller.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = ["arn:aws:automate:${var.region}:ec2:recover", aws_sns_topic.alarms.arn]
}
