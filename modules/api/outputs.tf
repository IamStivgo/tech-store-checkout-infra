output "http_api_id" {
  description = "ID of the HTTP API."
  value       = aws_apigatewayv2_api.http.id
}

output "http_api_domain" {
  description = "Domain of the HTTP API default endpoint, used as the CloudFront origin for /api/*."
  value       = replace(aws_apigatewayv2_api.http.api_endpoint, "https://", "")
}

output "function_names" {
  description = "Lambda function names by logical name (api, reconcile)."
  value       = { for key, function in aws_lambda_function.this : key => function.function_name }
}

output "function_arns" {
  description = "Unqualified Lambda function ARNs by logical name, for the deploy role."
  value       = { for key, function in aws_lambda_function.this : key => function.arn }
}

output "live_alias_arns" {
  description = "ARNs of the live alias of each function, invoked by API Gateway and the scheduler."
  value       = { for key, alias in aws_lambda_alias.live : key => alias.arn }
}
