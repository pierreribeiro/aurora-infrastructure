# Cluster configuration
cluster_name    = "ecommerce-prod"
engine          = "aurora-mysql"
engine_version  = "8.0.mysql_aurora.3.02.0"
database_name   = "ecommerce"
master_username = "admin"

# Network
vpc_id     = "vpc-12345678"
subnet_ids = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
allowed_cidr_blocks = ["10.0.0.0/16"]

# Instances
instances = {
  "ecommerce-prod-writer" = {
    instance_class               = "db.r6g.2xlarge"
    performance_insights_enabled = true
    monitoring_interval         = 60
    promotion_tier              = 0
  }
  "ecommerce-prod-reader-1" = {
    instance_class               = "db.r6g.xlarge"
    performance_insights_enabled = true
    monitoring_interval         = 60
    promotion_tier              = 1
  }
  "ecommerce-prod-reader-2" = {
    instance_class               = "db.r6g.xlarge"
    performance_insights_enabled = true
    monitoring_interval         = 60
    promotion_tier              = 2
  }
}

# Backup
backup_retention_period = 35
backup_window          = "03:00-04:00"
maintenance_window     = "sun:04:00-sun:05:00"

# Security
deletion_protection = true
skip_final_snapshot = false

# Auto Scaling
enable_autoscaling         = true
autoscaling_min_capacity   = 2
autoscaling_max_capacity   = 5
autoscaling_cpu_target     = 70

# Monitoring
alarm_cpu_threshold         = 80
alarm_connections_threshold = 900
alarm_sns_topics           = ["arn:aws:sns:us-east-1:123456789012:dba-alerts"]

# Tags
tags = {
  Environment = "production"
  Application = "ecommerce"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
}