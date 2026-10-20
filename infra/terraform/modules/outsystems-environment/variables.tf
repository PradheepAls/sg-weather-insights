# ---------------------------------------------------------------- identity

variable "project" {
  description = "Short project prefix used in names, e.g. sgw."
  type        = string
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
  description = "Enables production guard-rails (preconditions below fail the plan if they are not met)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------- network

variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "data_subnet_ids" { type = list(string) }

variable "lifetime_cidr" {
  description = "CIDR LifeTime connects from (LifeTime calls each environment's Service Center on 443)."
  type        = string
}

variable "alb_internal" {
  description = "Internal ALB (LifeTime, Dev, Test behind VPN) or internet-facing (Prod)."
  type        = bool
  default     = true
}

variable "alb_ingress_cidrs" {
  description = "Who may reach the ALB on 80/443."
  type        = list(string)
}

variable "admin_cidrs" {
  description = "Who may reach Service Center, LifeTime and test endpoints through the ALB. Max 5 (ALB condition limit)."
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) >= 1 && length(var.admin_cidrs) <= 5
    error_message = "Provide between 1 and 5 admin CIDRs."
  }
}

# ---------------------------------------------------------------- shared foundation

variable "kms_key_arn" { type = string }
variable "artifacts_bucket" { type = string }
variable "alb_logs_bucket" { type = string }
variable "alarm_topic_arn" { type = string }

# ---------------------------------------------------------------- DNS / TLS

variable "certificate_arn" {
  description = "ACM certificate for the ALB HTTPS listener."
  type        = string
}

variable "public_hostname" {
  description = "FQDN for the environment, e.g. weather-dev.example.gov.sg."
  type        = string
}

variable "public_zone_id" {
  description = "Route 53 zone for public_hostname. Empty = manage DNS outside Terraform."
  type        = string
  default     = ""
}

variable "private_zone_id" {
  description = "Private hosted zone shared by all environments (controller records live here)."
  type        = string
}

variable "private_zone_name" {
  type = string
}

# ---------------------------------------------------------------- OutSystems

variable "platform_server_version" {
  description = "Pinned Platform Server version installed by bootstrap. Upgrades are explicit changes."
  type        = string
  validation {
    condition     = can(regex("^11\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.platform_server_version))
    error_message = "platform_server_version must look like 11.x.y or 11.x.y.z."
  }
}

variable "license_s3_key" {
  description = "Key of the OutSystems license file in the artifacts bucket."
  type        = string
}

variable "dedicated_controller" {
  description = "Run the Deployment Controller on its own server (Prod) rather than doubling as a front-end."
  type        = bool
  default     = false
}

variable "controller_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "frontend_instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "frontend_min" {
  type    = number
  default = 0
}

variable "frontend_max" {
  type    = number
  default = 2
}

variable "frontend_desired" {
  type    = number
  default = 0
}

variable "root_volume_gb" {
  type    = number
  default = 120
}

variable "ami_ssm_parameter" {
  description = "Resolved at launch, so instances always start from the latest patched AMI."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "health_check_path" {
  description = "ALB health check. Bootstrap creates /lb-health.html; switch to the app's /health once deployed."
  type        = string
  default     = "/lb-health.html"
}

# ---------------------------------------------------------------- database

variable "db_engine" {
  description = "sqlserver-se (Standard) or sqlserver-ee. Express/Web are not suitable for OutSystems factories."
  type        = string
  default     = "sqlserver-se"
  validation {
    condition     = contains(["sqlserver-se", "sqlserver-ee"], var.db_engine)
    error_message = "db_engine must be sqlserver-se or sqlserver-ee."
  }
}

variable "db_engine_version" {
  description = "Major version; RDS picks the latest minor and auto-upgrades minors."
  type        = string
  default     = "16.00"
}

variable "db_instance_class" {
  type    = string
  default = "db.m6i.large"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 100
}

variable "db_max_allocated_storage_gb" {
  type    = number
  default = 500
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_force_ssl" {
  description = "Require TLS to SQL Server (rds.force_ssl). Bootstrap trusts the RDS CA bundle."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------- edge

variable "enable_waf" {
  type    = bool
  default = false
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per 5 minutes per client IP before WAF blocks."
  type        = number
  default     = 2000
}

# ---------------------------------------------------------------- ops

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "patch_operation" {
  description = "Weekly SSM patch baseline run: Install (non-prod) or Scan (prod, patched in a change window)."
  type        = string
  default     = "Install"
  validation {
    condition     = contains(["Install", "Scan"], var.patch_operation)
    error_message = "patch_operation must be Install or Scan."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
