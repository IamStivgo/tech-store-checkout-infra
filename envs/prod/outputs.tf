output "app_url" {
  description = "Public URL of the application (SPA and /api/*)."
  value       = "https://${module.static_site.cloudfront_domain}"
}

output "spa_bucket_name" {
  description = "S3 bucket of the SPA build."
  value       = module.static_site.bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID, for cache invalidations."
  value       = module.static_site.distribution_id
}

output "dynamodb_table_names" {
  description = "DynamoDB table names by logical name."
  value       = module.database.table_names
}

output "http_api_domain" {
  description = "Domain of the HTTP API default endpoint."
  value       = module.api.http_api_domain
}

output "lambda_function_names" {
  description = "Lambda function names by logical name (api, reconcile)."
  value       = module.api.function_names
}

output "payment_parameter_names" {
  description = "SSM parameters to create with the AWS CLI for the payment provider secrets."
  value       = module.secrets.parameter_names
}
