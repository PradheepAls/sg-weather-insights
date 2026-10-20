output "kms_key_arn" { value = aws_kms_key.this.arn }
output "artifacts_bucket" { value = aws_s3_bucket.artifacts.bucket }
output "artifacts_bucket_arn" { value = aws_s3_bucket.artifacts.arn }
output "alb_logs_bucket" { value = aws_s3_bucket.alb_logs.bucket }
output "alarm_topic_arn" { value = aws_sns_topic.alarms.arn }
output "ci_plan_role_arn" { value = try(aws_iam_role.ci_plan[0].arn, null) }
output "ci_apply_role_arn" { value = try(aws_iam_role.ci_apply[0].arn, null) }
