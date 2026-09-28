variable "name_prefix" {
  description = "Prefix for every resource name, as <project>-<environment> (e.g. checkout-app-prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_prefix))
    error_message = "name_prefix must be lowercase kebab-case (letters, digits and hyphens)."
  }
}

variable "app_env" {
  description = "Logical environment passed to the application as APP_ENV."
  type        = string

  validation {
    condition     = contains(["local", "test", "prod"], var.app_env)
    error_message = "app_env must be local, test or prod (the values accepted by the api configuration)."
  }
}

variable "log_level" {
  description = "Application log level (LOG_LEVEL)."
  type        = string
  default     = "info"

  validation {
    condition     = contains(["fatal", "error", "warn", "info", "debug", "trace"], var.log_level)
    error_message = "log_level must be a pino level: fatal, error, warn, info, debug or trace."
  }
}

variable "log_retention_days" {
  description = "Retention of the Lambda and API Gateway log groups."
  type        = number
  default     = 14
}

variable "placeholder_source_dir" {
  description = "Folder with lambda.js and reconcile.js, used only to create the functions."
  type        = string
}

variable "table_names" {
  description = "DynamoDB table names by logical name (output of the database module)."
  type        = map(string)

  validation {
    condition = alltrue([
      for table in ["products", "customers", "transactions", "deliveries", "idempotency-keys", "transaction-events"] :
      contains(keys(var.table_names), table)
    ])
    error_message = "table_names must include every table of the data model."
  }
}

variable "table_arns" {
  description = "DynamoDB table ARNs by logical name (output of the database module)."
  type        = map(string)
}

variable "payment_parameter_names" {
  description = "SSM parameter names of the payment provider secrets by logical name (output of the secrets module)."
  type        = map(string)

  validation {
    condition     = toset(keys(var.payment_parameter_names)) == toset(["private-key", "integrity-secret", "events-secret"])
    error_message = "payment_parameter_names must contain private-key, integrity-secret and events-secret."
  }
}

variable "payment_parameter_arns" {
  description = "SSM parameter ARNs of the payment provider secrets by logical name (output of the secrets module)."
  type        = map(string)
}

variable "payment_api_base_url" {
  description = "Base URL of the payment provider API (e.g. its sandbox), without a trailing slash."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+(/[a-z0-9/-]*[a-z0-9])?$", var.payment_api_base_url))
    error_message = "payment_api_base_url must be an https URL without a trailing slash."
  }
}

variable "payment_public_key" {
  description = "Public key of the payment provider merchant; the private secrets stay in SSM."
  type        = string
  sensitive   = true
}

variable "origin_verify_secret" {
  description = "Secret CloudFront sends to the API in x-origin-verify; the API refuses requests without it (T-086)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.origin_verify_secret) >= 32
    error_message = "origin_verify_secret must have at least 32 characters."
  }
}
