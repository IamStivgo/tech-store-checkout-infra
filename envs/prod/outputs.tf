output "dynamodb_table_names" {
  description = "DynamoDB table names by logical name."
  value       = module.database.table_names
}
