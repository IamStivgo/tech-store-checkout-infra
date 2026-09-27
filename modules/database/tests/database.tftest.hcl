mock_provider "aws" {}

variables {
  name_prefix = "checkout-app-test"
}

run "creates_the_six_tables_with_the_prefix" {
  command = plan

  assert {
    condition = toset(keys(aws_dynamodb_table.this)) == toset([
      "products", "customers", "transactions", "deliveries", "idempotency-keys", "transaction-events",
    ])
    error_message = "The module must create exactly the six tables of the data model."
  }

  assert {
    condition     = aws_dynamodb_table.this["products"].name == "checkout-app-test-products"
    error_message = "Table names must be <name_prefix>-<table>."
  }
}

run "every_table_is_on_demand_recoverable_and_protected" {
  command = plan

  assert {
    condition     = alltrue([for table in aws_dynamodb_table.this : table.billing_mode == "PAY_PER_REQUEST"])
    error_message = "Every table must use on-demand billing."
  }

  assert {
    condition     = alltrue([for table in aws_dynamodb_table.this : table.point_in_time_recovery[0].enabled])
    error_message = "Every table must have point-in-time recovery."
  }

  assert {
    condition     = alltrue([for table in aws_dynamodb_table.this : table.deletion_protection_enabled])
    error_message = "Every table must have deletion protection."
  }
}

run "transactions_have_reference_and_sparse_pending_indexes" {
  command = plan

  assert {
    condition = toset([for index in aws_dynamodb_table.this["transactions"].global_secondary_index : index.name]) == toset([
      "reference-index", "pending-index",
    ])
    error_message = "transactions must have the reference-index and pending-index GSIs."
  }

  assert {
    condition = anytrue([
      for index in aws_dynamodb_table.this["transactions"].global_secondary_index :
      index.name == "pending-index" && toset([
        for key in index.key_schema : "${key.key_type}:${key.attribute_name}"
      ]) == toset(["HASH:pendingBucket", "RANGE:pendingSince"])
    ])
    error_message = "pending-index must be keyed by pendingBucket (HASH) and pendingSince (RANGE)."
  }
}

run "only_idempotency_keys_expire" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this["idempotency-keys"].ttl[0].attribute_name == "expiresAt"
    error_message = "idempotency-keys must expire through the expiresAt TTL attribute."
  }

  assert {
    condition     = length(aws_dynamodb_table.this["transaction-events"].ttl) == 0
    error_message = "The audit trail must never expire."
  }
}

run "transaction_events_are_ordered_by_event_key" {
  command = plan

  assert {
    condition = (
      aws_dynamodb_table.this["transaction-events"].hash_key == "transactionId" &&
      aws_dynamodb_table.this["transaction-events"].range_key == "eventKey"
    )
    error_message = "transaction-events must be keyed by transactionId and eventKey."
  }
}

run "rejects_invalid_name_prefixes" {
  command = plan

  variables {
    name_prefix = "Checkout_App"
  }

  expect_failures = [var.name_prefix]
}
