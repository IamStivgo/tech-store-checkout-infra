variable "parameter_prefix" {
  description = "SSM path prefix for the environment, as /<project>/<environment> (e.g. /checkout-app/prod)."
  type        = string

  validation {
    condition     = can(regex("^(/[a-z0-9]+(-[a-z0-9]+)*)+$", var.parameter_prefix))
    error_message = "parameter_prefix must be an absolute SSM path of lowercase kebab-case segments, without a trailing slash."
  }
}
