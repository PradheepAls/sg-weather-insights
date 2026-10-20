variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project" {
  type    = string
  default = "sgw"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "nonprod_cidr" {
  description = "LifeTime, Dev and Test."
  type        = string
  default     = "10.20.0.0/16"
}

variable "prod_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "private_zone_name" {
  type    = string
  default = "sgw.internal"
}

variable "alarm_emails" {
  type    = list(string)
  default = []
}

variable "github_repository" {
  type    = string
  default = ""
}
