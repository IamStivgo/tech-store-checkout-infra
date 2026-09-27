variable "name_prefix" {
  description = "Prefix for every resource name, as <project>-<environment> (e.g. checkout-app-prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_prefix))
    error_message = "name_prefix must be lowercase kebab-case (letters, digits and hyphens)."
  }
}

variable "target_function_arn" {
  description = "Qualified ARN (live alias) of the reconcile Lambda function."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$", var.target_function_arn))
    error_message = "target_function_arn must be a qualified Lambda ARN (function:<name>:<alias>)."
  }
}

variable "schedule_expression" {
  description = "How often reconciliation runs."
  type        = string
  default     = "rate(5 minutes)"

  validation {
    condition     = can(regex("^(rate|cron)\\(.+\\)$", var.schedule_expression))
    error_message = "schedule_expression must be a rate(...) or cron(...) expression."
  }
}
