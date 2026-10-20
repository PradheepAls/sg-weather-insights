variable "name" {
  description = "Name prefix, e.g. sgw-nonprod."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. Must not overlap with peered VPCs."
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) <= 20
    error_message = "cidr_block must be a valid IPv4 CIDR of /20 or larger (three tiers x two AZs need room)."
  }
}

variable "azs" {
  description = "Availability zones to span. Two is the minimum for ALB and RDS Multi-AZ."
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use two or three AZs."
  }
}

variable "nat_gateway_per_az" {
  description = "One NAT gateway per AZ (prod) instead of a single shared one (non-prod, cheaper, single-AZ egress)."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}

variable "kms_key_arn" {
  description = "CMK for flow-log encryption."
  type        = string
}

variable "interface_endpoints" {
  description = "Interface VPC endpoints so instances reach SSM, Secrets Manager and CloudWatch without the internet."
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "secretsmanager", "logs", "monitoring", "kms"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
