variable "github_repository" {
  description = "GitHub repository whose workflows may assume the Terraform roles, as <owner>@<owner_id>/<name>@<repository_id> (the immutable OIDC subject format)."
  type        = string
  default     = "IamStivgo@94694810/tech-store-checkout-infra@1388345805"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+@[0-9]+/[A-Za-z0-9._-]+@[0-9]+$", var.github_repository))
    error_message = "github_repository must be <owner>@<owner_id>/<name>@<repository_id>."
  }
}
