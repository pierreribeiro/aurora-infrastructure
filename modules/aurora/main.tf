### 1.2 Módulo Aurora Completo

# KMS Key para criptografia
resource "aws_kms_key" "aurora" {
  description             = "KMS key for Aurora cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-aurora-kms"
    }
  )
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.cluster_name}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

# Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.cluster_name}-aurora-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-aurora-subnet-group"
    }
  )
}

# Parameter Groups
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.cluster_name}-aurora-cluster-params"
  family      = var.parameter_group_family
  description = "Custom cluster parameter group for ${var.cluster_name}"

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_db_parameter_group" "aurora" {
  name        = "${var.cluster_name}-aurora-instance-params"
  family      = var.parameter_group_family
  description = "Custom instance parameter group for ${var.cluster_name}"

  dynamic "parameter" {
    for_each = var.instance_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Security Group
resource "aws_security_group" "aurora" {
  name_prefix = "${var.cluster_name}-aurora-"
  description = "Security group for Aurora cluster ${var.cluster_name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "MySQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-aurora-sg"
    }
  )
}

# Aurora Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = var.cluster_name
  engine                         = var.engine
  engine_version                 = var.engine_version
  engine_mode                    = var.engine_mode
  database_name                  = var.database_name
  master_username                = var.master_username
  master_password                = var.create_random_password ? random_password.master[0].result : var.master_password
  
  db_subnet_group_name           = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids         = [aws_security_group.aurora.id]
  
  storage_encrypted              = true
  kms_key_id                    = aws_kms_key.aurora.arn
  
  backup_retention_period        = var.backup_retention_period
  preferred_backup_window        = var.backup_window
  preferred_maintenance_window   = var.maintenance_window
  
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  
  skip_final_snapshot            = var.skip_final_snapshot
  final_snapshot_identifier      = var.skip_final_snapshot ? null : "${var.cluster_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  deletion_protection            = var.deletion_protection
  
  # Serverless v2 configuration
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
    }
  }
  
  # Global cluster configuration
  global_cluster_identifier = var.global_cluster_identifier
  
  # Backtrack window (MySQL only)
  backtrack_window = var.engine == "aurora-mysql" ? var.backtrack_window : null
  
  tags = var.tags
  
  lifecycle {
    ignore_changes = [master_password]
  }
}

# Random password for master user
resource "random_password" "master" {
  count   = var.create_random_password ? 1 : 0
  length  = 32
  special = true
}

# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "aurora_master_password" {
  count       = var.create_random_password ? 1 : 0
  name_prefix = "${var.cluster_name}-aurora-master-password-"
  description = "Master password for Aurora cluster ${var.cluster_name}"
  
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "aurora_master_password" {
  count         = var.create_random_password ? 1 : 0
  secret_id     = aws_secretsmanager_secret.aurora_master_password[0].id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora.master_username
    password = random_password.master[0].result
    engine   = var.engine
    host     = aws_rds_cluster.aurora.endpoint
    port     = aws_rds_cluster.aurora.port
    dbname   = aws_rds_cluster.aurora.database_name
  })
}

# Aurora Instances
resource "aws_rds_cluster_instance" "aurora" {
  for_each = var.instances

  identifier                   = each.key
  cluster_identifier          = aws_rds_cluster.aurora.id
  instance_class              = each.value.instance_class
  engine                      = aws_rds_cluster.aurora.engine
  engine_version              = aws_rds_cluster.aurora.engine_version
  db_parameter_group_name     = aws_db_parameter_group.aurora.name
  
  performance_insights_enabled = each.value.performance_insights_enabled
  performance_insights_kms_key_id = each.value.performance_insights_enabled ? aws_kms_key.aurora.arn : null
  performance_insights_retention_period = each.value.performance_insights_enabled ? var.performance_insights_retention_period : null
  
  monitoring_interval         = each.value.monitoring_interval
  monitoring_role_arn        = each.value.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  promotion_tier            = each.value.promotion_tier
  
  tags = merge(
    var.tags,
    {
      Name = each.key
      Type = each.value.promotion_tier == 0 ? "writer" : "reader"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "enhanced_monitoring" {
  count = var.create_monitoring_role ? 1 : 0
  
  name_prefix = "${var.cluster_name}-aurora-monitoring-"
  
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
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.create_monitoring_role ? 1 : 0
  
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Auto Scaling
resource "aws_appautoscaling_target" "read_replicas" {
  count = var.enable_autoscaling ? 1 : 0
  
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "cluster:${aws_rds_cluster.aurora.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0
  
  name               = "${var.cluster_name}-aurora-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_replicas[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read_replicas[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_replicas[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.cluster_name}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  alarm_description   = "Aurora cluster CPU utilization is too high"
  alarm_actions       = var.alarm_sns_topics
  
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "connections_high" {
  alarm_name          = "${var.cluster_name}-aurora-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_connections_threshold
  alarm_description   = "Aurora cluster has too many connections"
  alarm_actions       = var.alarm_sns_topics
  
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }
  
  tags = var.tags
}