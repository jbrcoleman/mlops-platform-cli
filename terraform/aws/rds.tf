# RDS PostgreSQL for MLflow Backend Store

# Random password for RDS master user
resource "random_password" "rds_master_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_master_password" {
  name_prefix             = "${local.cluster_name}-rds-master-"
  description             = "Master password for MLflow RDS database"
  recovery_window_in_days = 7

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-rds-master-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id = aws_secretsmanager_secret.rds_master_password.id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds_master_password.result
    engine   = "postgres"
    host     = aws_db_instance.mlflow.address
    port     = aws_db_instance.mlflow.port
    dbname   = var.rds_database_name
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "mlflow" {
  name_prefix = "${local.cluster_name}-mlflow-"
  description = "Subnet group for MLflow RDS instance"
  subnet_ids  = module.vpc.database_subnets

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-mlflow-db-subnet"
    }
  )
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${local.cluster_name}-rds-"
  description = "Security group for MLflow RDS instance"
  vpc_id      = module.vpc.vpc_id

  # Allow PostgreSQL from EKS nodes
  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # Allow PostgreSQL from VPC (for debugging/management)
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_cidr_blocks) > 0 ? var.allowed_cidr_blocks : [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-rds-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "mlflow" {
  name_prefix = "${local.cluster_name}-mlflow-"
  family      = "postgres15"
  description = "Custom parameter group for MLflow PostgreSQL"

  # Only set dynamic parameters that don't require DB restart
  # Static parameters (shared_buffers, max_connections) use RDS defaults

  parameter {
    name  = "log_statement"
    value = "ddl"  # Log DDL statements (less verbose than "all")
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking more than 1 second
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000"  # 5 minutes - prevent hung transactions
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-mlflow-db-params"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "mlflow" {
  identifier_prefix = "${local.cluster_name}-mlflow-"

  # Engine configuration
  engine               = "postgres"
  engine_version       = var.rds_engine_version
  instance_class       = var.rds_instance_class
  allocated_storage    = var.rds_allocated_storage
  storage_type         = "gp3"
  storage_encrypted    = true
  kms_key_id          = aws_kms_key.rds.arn

  # Database configuration
  db_name  = var.rds_database_name
  username = var.rds_master_username
  password = random_password.rds_master_password.result
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.mlflow.name

  # Backup configuration
  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "03:00-04:00" # UTC
  maintenance_window     = "mon:04:00-mon:05:00" # UTC

  # Enable automated backups
  skip_final_snapshot       = var.environment == "dev" ? true : false
  final_snapshot_identifier = var.environment == "dev" ? null : "${local.cluster_name}-mlflow-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  copy_tags_to_snapshot     = true

  # Deletion protection
  deletion_protection = var.enable_deletion_protection

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn            = aws_iam_role.rds_monitoring.arn

  # Performance Insights
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-mlflow-db"
    }
  )

  depends_on = [
    aws_db_subnet_group.mlflow,
    aws_security_group.rds
  ]
}

# KMS Key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS instance ${local.cluster_name}-mlflow encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-rds-key"
    }
  )
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.cluster_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name_prefix = "${local.cluster_name}-rds-monitoring-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-rds-monitoring-role"
    }
  )
}

# Attach Enhanced Monitoring policy
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.cluster_name}-rds-cpu-utilization"
  alarm_description   = "RDS CPU utilization is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mlflow.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.cluster_name}-rds-free-storage"
  alarm_description   = "RDS free storage space is low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000000000" # 5 GB in bytes

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mlflow.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.cluster_name}-rds-database-connections"
  alarm_description   = "RDS database connections are high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "180" # 90% of max_connections (200)

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mlflow.id
  }

  tags = local.common_tags
}
