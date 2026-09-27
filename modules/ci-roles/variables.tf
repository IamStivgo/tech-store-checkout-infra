variable "name_prefix" {
  description = "Prefix for every role name, as <project>-<environment> (e.g. checkout-app-prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_prefix))
    error_message = "name_prefix must be lowercase kebab-case (letters, digits and hyphens)."
  }
}

variable "parameter_prefix" {
  description = "SSM path prefix for the environment, as /<project>/<environment> (e.g. /checkout-app/prod)."
  type        = string

  validation {
    condition     = can(regex("^(/[a-z0-9]+(-[a-z0-9]+)*)+$", var.parameter_prefix))
    error_message = "parameter_prefix must be an absolute SSM path of lowercase kebab-case segments, without a trailing slash."
  }
}

variable "web_repository" {
  description = "GitHub repository of the web app, as <owner>/<name>."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.web_repository))
    error_message = "web_repository must be <owner>/<name>."
  }
}

variable "api_repository" {
  description = "GitHub repository of the API, as <owner>/<name>."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.api_repository))
    error_message = "api_repository must be <owner>/<name>."
  }
}

variable "spa_bucket_name" {
  description = "S3 bucket of the SPA build (output of the static-site module)."
  type        = string
}

variable "spa_bucket_arn" {
  description = "ARN of the SPA bucket (output of the static-site module)."
  type        = string
}

variable "distribution_id" {
  description = "CloudFront distribution ID (output of the static-site module)."
  type        = string
}

variable "distribution_arn" {
  description = "CloudFront distribution ARN (output of the static-site module)."
  type        = string
}

variable "app_url" {
  description = "Public URL of the application, used by the deploy smoke tests."
  type        = string

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+$", var.app_url))
    error_message = "app_url must be https://<host>, without path."
  }
}

variable "function_names" {
  description = "Lambda function names by logical name (output of the api module)."
  type        = map(string)

  validation {
    condition     = toset(keys(var.function_names)) == toset(["api", "reconcile"])
    error_message = "function_names must contain api and reconcile."
  }
}

variable "function_arns" {
  description = "Unqualified Lambda function ARNs by logical name (output of the api module)."
  type        = map(string)
}

variable "products_table_name" {
  description = "Name of the products table, the only one the seed writes."
  type        = string
}

variable "products_table_arn" {
  description = "ARN of the products table."
  type        = string
}
