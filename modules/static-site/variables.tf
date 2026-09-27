variable "name_prefix" {
  description = "Prefix for every resource name, as <project>-<environment> (e.g. checkout-app-prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_prefix))
    error_message = "name_prefix must be lowercase kebab-case (letters, digits and hyphens)."
  }
}

variable "api_domain" {
  description = "Domain of the HTTP API default endpoint, origin of the /api/* behavior."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", var.api_domain))
    error_message = "api_domain must be the bare API Gateway domain, without scheme or path."
  }
}

variable "csp_connect_origins" {
  description = "Extra origins the SPA may call besides itself (Content-Security-Policy connect-src), e.g. the payment provider sandbox."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for origin in var.csp_connect_origins : can(regex("^https://[a-z0-9.-]+$", origin))])
    error_message = "Every origin must be https://<host>, without path."
  }
}
