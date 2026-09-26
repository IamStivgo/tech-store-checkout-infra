locals {
  # Only key attributes are declared: DynamoDB is schemaless for the rest of the item.
  tables = {
    products = {
      hash_key   = "productId"
      range_key  = null
      attributes = { productId = "S" }
      indexes    = {}
      ttl        = null
    }

    customers = {
      hash_key   = "customerId"
      range_key  = null
      attributes = { customerId = "S" }
      indexes    = {}
      ttl        = null
    }

    transactions = {
      hash_key  = "transactionId"
      range_key = null
      attributes = {
        transactionId = "S"
        reference     = "S"
        pendingBucket = "S"
        pendingSince  = "S"
      }
      indexes = {
        # Lookup by payment reference (webhook and provider searches).
        reference-index = { HASH = "reference" }
        # Sparse index: only PENDING transactions carry pendingBucket, so reconciliation never scans.
        pending-index = { HASH = "pendingBucket", RANGE = "pendingSince" }
      }
      ttl = null
    }

    deliveries = {
      hash_key   = "deliveryId"
      range_key  = null
      attributes = { deliveryId = "S" }
      indexes    = {}
      ttl        = null
    }

    idempotency-keys = {
      hash_key   = "idempotencyKey"
      range_key  = null
      attributes = { idempotencyKey = "S" }
      indexes    = {}
      ttl        = "expiresAt"
    }

    # Append-only audit trail; immutability is enforced by the Lambda IAM policies.
    transaction-events = {
      hash_key   = "transactionId"
      range_key  = "eventKey"
      attributes = { transactionId = "S", eventKey = "S" }
      indexes    = {}
      ttl        = null
    }
  }
}

resource "aws_dynamodb_table" "this" {
  for_each = local.tables

  name                        = "${var.name_prefix}-${each.key}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = each.value.hash_key
  range_key                   = each.value.range_key
  deletion_protection_enabled = true

  dynamic "attribute" {
    for_each = each.value.attributes

    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.indexes

    content {
      name            = global_secondary_index.key
      projection_type = "ALL"

      dynamic "key_schema" {
        for_each = global_secondary_index.value

        content {
          attribute_name = key_schema.value
          key_type       = key_schema.key
        }
      }
    }
  }

  dynamic "ttl" {
    for_each = each.value.ttl == null ? [] : [each.value.ttl]

    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = true
  }
}
