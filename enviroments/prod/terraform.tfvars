variable "cluster_name" {
  description = "Name of the Aurora cluster"
  type        = string
}

variable "engine" {
  description = "Aurora engine type"
  type        = string
  default     = "aurora-mysql"
  
  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.engine)
    error_message = "Engine must be either aurora-mysql or aurora-postgresql"
  }
}

variable "engine_version" {
  description = "Aurora engine version"
  type        = string
}

variable "engine_mode" {
  description = "Aurora engine mode"
  type        = string
  default     = "provisioned"
  
  validation {
    condition     = contains(["provisioned", "serverless"], var.engine_mode)
    error_message = "Engine mode must be either provisioned or serverless"
  }
}

variable "instances" {
  description = "Map of cluster instances and their configuration"
  type = map(object({
    instance_class               = string
    performance_insights_enabled = bool
    monitoring_interval         = number
    promotion_tier             = number
  }))
  
  default = {
    writer = {
      instance_class               = "db.r6g.large"
      performance_insights_enabled = true
      monitoring_interval         = 60
      promotion_tier              = 0
    }
  }
}

variable "serverlessv2_scaling_configuration" {
  description = "Serverless v2 scaling configuration"
  type = object({
    max_capacity = number
    min_capacity = number
  })
  default = null
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect to the cluster"
  type        = list(string)
  default     = []
}

# ... mais variáveis ...