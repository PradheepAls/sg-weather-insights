resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = var.data_subnet_ids
  tags       = local.tags
}

resource "aws_db_parameter_group" "this" {
  name   = local.name
  family = "${var.db_engine}-${split(".", var.db_engine_version)[0]}.0"

  parameter {
    name         = "rds.force_ssl"
    value        = var.db_force_ssl ? "1" : "0"
    apply_method = "pending-reboot"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = local.name
  engine         = var.db_engine
  engine_version = var.db_engine_version
  license_model  = "license-included"
  instance_class = var.db_instance_class

  # OutSystems expects case-insensitive, accent-sensitive Latin1 collation.
  character_set_name = "SQL_Latin1_General_CP1_CI_AS"
  # Same wall-clock as the servers (Singapore has no DST), so platform timestamps align.
  timezone = "Singapore Standard Time"

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username                      = "osmaster"
  manage_master_user_password   = true # RDS owns and can rotate it; OutSystems uses its own logins
  master_user_secret_kms_key_id = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  backup_retention_period   = var.db_backup_retention_days
  backup_window             = "18:00-19:00" # 02:00-03:00 SGT
  maintenance_window        = "sat:19:30-sat:20:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.is_production
  final_snapshot_identifier = "${local.name}-final"

  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports       = ["error", "agent"]

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !var.is_production || (var.db_multi_az && var.deletion_protection && var.db_backup_retention_days >= 14)
      error_message = "Production databases require Multi-AZ, deletion protection and at least 14 days of backups."
    }
  }
}
