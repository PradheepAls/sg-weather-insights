variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  description = "OutSystems environment this stack provisions."
  type        = string
  validation {
    condition     = contains(["lifetime", "dev", "test", "prod"], var.environment)
    error_message = "environment must be one of lifetime, dev, test, prod."
  }
}

variable "is_production" {
  description = "Turns on production guard-rails; the plan fails if they are not met."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- network

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
  validation {
    condition     = length(var.azs) == 2
    error_message = "Use exactly two AZs (ALB and RDS Multi-AZ need two)."
  }
}

variable "alb_internal" {
  description = "Internal ALB (reached over VPN) or internet-facing."
  type        = bool
  default     = true
}

variable "alb_ingress_cidrs" {
  description = "Who may reach the application on 80/443."
  type        = list(string)
}

variable "admin_cidrs" {
  description = "Only these networks may open Service Center / LifeTime through the ALB (max 5)."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) >= 1 && length(var.admin_cidrs) <= 5
    error_message = "Provide between 1 and 5 admin CIDRs."
  }
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener."
  type        = string
}

# ---------------------------------------------------------------- OutSystems

variable "platform_server_version" {
  description = "Pinned Platform Server version installed at first boot."
  type        = string
  validation {
    condition     = can(regex("^11\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.platform_server_version))
    error_message = "platform_server_version must look like 11.x.y or 11.x.y.z."
  }
}

variable "license_bucket" {
  description = "Existing S3 bucket holding the OutSystems licence file."
  type        = string
}

variable "license_key" {
  description = "Object key of the licence file, e.g. licenses/dev.lic."
  type        = string
}

variable "controller_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "frontend_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "frontend_count" {
  description = "Extra front-end servers. 0 = the controller also serves traffic (non-prod)."
  type        = number
  default     = 0
}

# ---------------------------------------------------------------- database

variable "db_instance_class" {
  type    = string
  default = "db.m6i.large"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------- ops

variable "alarm_email" {
  description = "Optional address subscribed to alarms."
  type        = string
  default     = ""
}
