output "dynamodb_table_names" {
  description = "DynamoDB table names by logical name."
  value       = module.database.table_names
}

output "payment_parameter_names" {
  description = "SSM parameters to create with the AWS CLI for the payment provider secrets."
  value       = module.secrets.parameter_names
}
