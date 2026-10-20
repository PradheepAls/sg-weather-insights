variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project" {
  type    = string
  default = "sgw"
}

variable "state_bucket" {
  description = "Bucket holding foundation.tfstate."
  type        = string
}

variable "environment" { type = string }
variable "network" {
  description = "nonprod or prod: which foundation VPC hosts this environment."
  type        = string
  validation {
    condition     = contains(["nonprod", "prod"], var.network)
    error_message = "network must be nonprod or prod."
  }
}
variable "is_production" {
  type    = bool
  default = false
}

variable "public_hostname" { type = string }
variable "public_zone_id" {
  type    = string
  default = ""
}
variable "certificate_arn" { type = string }
variable "alb_internal" { type = bool }
variable "alb_ingress_cidrs" { type = list(string) }
variable "admin_cidrs" { type = list(string) }

variable "platform_server_version" { type = string }
variable "license_s3_key" { type = string }
variable "dedicated_controller" {
  type    = bool
  default = false
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
  default = 0
}
variable "frontend_desired" {
  type    = number
  default = 0
}

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
variable "enable_waf" {
  type    = bool
  default = false
}
variable "patch_operation" {
  type    = string
  default = "Install"
}
