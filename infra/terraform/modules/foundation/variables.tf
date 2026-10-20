variable "name" {
  description = "Name prefix, e.g. sgw."
  type        = string
}

variable "alarm_emails" {
  description = "Addresses subscribed to the alarm topic (confirm the subscription email)."
  type        = list(string)
  default     = []
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI roles through GitHub OIDC. Empty disables CI roles."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "tags" {
  type    = map(string)
  default = {}
}
