output "table_names" {
  description = "Table names by logical name (products, customers, transactions, deliveries, idempotency-keys, transaction-events)."
  value       = { for key, table in aws_dynamodb_table.this : key => table.name }
}

output "table_arns" {
  description = "Table ARNs by logical name, for IAM policies."
  value       = { for key, table in aws_dynamodb_table.this : key => table.arn }
}
