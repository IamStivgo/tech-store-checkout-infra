# Given by the pipelines from repository secrets (TF_VAR_*), never committed.

variable "payment_api_base_url" {
  description = "Base URL of the payment provider API."
  type        = string
  sensitive   = true
}

variable "payment_public_key" {
  description = "Public key of the payment provider merchant."
  type        = string
  sensitive   = true
}

variable "origin_verify_secret" {
  description = "Secret CloudFront sends to the API so it only answers requests from the CDN."
  type        = string
  sensitive   = true
}
