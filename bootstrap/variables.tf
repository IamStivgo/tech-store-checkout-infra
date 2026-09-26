variable "github_repository" {
  description = "GitHub repository, as <owner>/<name>, whose workflows may assume the Terraform roles."
  type        = string
  default     = "IamStivgo/tech-store-checkout-infra"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be <owner>/<name>."
  }
}
