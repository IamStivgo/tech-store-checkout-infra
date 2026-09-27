locals {
  business_tables = ["products", "customers", "transactions", "deliveries", "idempotency-keys"]

  # Table and index ARNs, so Query can use the transactions GSIs.
  table_resources = {
    for table, arn in var.table_arns : table => [arn, "${arn}/index/*"]
  }

  read_payment_secrets = {
    Sid      = "ReadPaymentSecrets"
    Effect   = "Allow"
    Action   = "ssm:GetParameters"
    Resource = values(var.payment_parameter_arns)
  }

  # transaction-events is an append-only audit trail: no function may update or delete it.
  append_audit_events = {
    Sid      = "AppendAuditEvents"
    Effect   = "Allow"
    Action   = ["dynamodb:PutItem", "dynamodb:ConditionCheckItem"]
    Resource = var.table_arns["transaction-events"]
  }

  write_own_logs = {
    for function in keys(local.functions) : function => {
      Sid      = "WriteOwnLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.function[function].arn}:*"
    }
  }

  function_policies = {
    api = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ReadWriteBusinessTables"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query",
            "dynamodb:ConditionCheckItem",
          ]
          Resource = flatten([for table in local.business_tables : local.table_resources[table]])
        },
        {
          Sid      = "ScanCatalog"
          Effect   = "Allow"
          Action   = "dynamodb:Scan"
          Resource = var.table_arns["products"]
        },
        {
          Sid      = "ExpireIdempotencyKeys"
          Effect   = "Allow"
          Action   = "dynamodb:DeleteItem"
          Resource = var.table_arns["idempotency-keys"]
        },
        local.append_audit_events,
        {
          Sid      = "ReadAuditEvents"
          Effect   = "Allow"
          Action   = "dynamodb:Query"
          Resource = var.table_arns["transaction-events"]
        },
        local.read_payment_secrets,
        local.write_own_logs["api"],
      ]
    }

    reconcile = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ReconcileTransactions"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query",
            "dynamodb:ConditionCheckItem",
          ]
          Resource = flatten([for table in ["transactions", "products", "deliveries"] : local.table_resources[table]])
        },
        local.append_audit_events,
        local.read_payment_secrets,
        local.write_own_logs["reconcile"],
      ]
    }
  }
}
