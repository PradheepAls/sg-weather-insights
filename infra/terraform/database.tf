resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "this" {
  identifier         = local.name
  engine             = "sqlserver-se"
  engine_version     = "16.00" # SQL Server 2022; RDS picks and patches the minor version
  license_model      = "license-included"
  instance_class     = var.db_instance_class
  character_set_name = "SQL_Latin1_General_CP1_CI_AS"
  timezone           = "Singapore Standard Time" # same wall-clock as the servers

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  username                      = "osmaster"
  manage_master_user_password   = true # RDS generates and stores it; OutSystems uses its own logins
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period         = var.db_backup_retention_days
  backup_window                   = "18:00-19:00" # 02:00 SGT
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = !var.is_production
  final_snapshot_identifier       = "${local.name}-final"
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.this.arn
  enabled_cloudwatch_logs_exports = ["error"]

  lifecycle {
    precondition {
      condition     = !var.is_production || (var.db_multi_az && var.deletion_protection && var.db_backup_retention_days >= 14)
      error_message = "Production needs a Multi-AZ database with deletion protection and at least 14 days of backups."
    }
  }
}
