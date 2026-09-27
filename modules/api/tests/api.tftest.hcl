mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/checkout-app-test-lambda"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/checkout-app-test"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test"
    }
  }

  mock_resource "aws_lambda_alias" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test:live"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test:live/invocations"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      api_endpoint  = "https://abc123.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:abc123"
    }
  }
}

variables {
  name_prefix            = "checkout-app-test"
  app_env                = "prod"
  placeholder_source_dir = "../../placeholder"

  table_names = {
    products           = "checkout-app-test-products"
    customers          = "checkout-app-test-customers"
    transactions       = "checkout-app-test-transactions"
    deliveries         = "checkout-app-test-deliveries"
    idempotency-keys   = "checkout-app-test-idempotency-keys"
    transaction-events = "checkout-app-test-transaction-events"
  }

  table_arns = {
    products           = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-products"
    customers          = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-customers"
    transactions       = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-transactions"
    deliveries         = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-deliveries"
    idempotency-keys   = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-idempotency-keys"
    transaction-events = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-transaction-events"
  }

  payment_parameter_names = {
    private-key      = "/checkout-app/test/payment/private-key"
    integrity-secret = "/checkout-app/test/payment/integrity-secret"
    events-secret    = "/checkout-app/test/payment/events-secret"
  }

  payment_parameter_arns = {
    private-key      = "arn:aws:ssm:us-east-1:123456789012:parameter/checkout-app/test/payment/private-key"
    integrity-secret = "arn:aws:ssm:us-east-1:123456789012:parameter/checkout-app/test/payment/integrity-secret"
    events-secret    = "arn:aws:ssm:us-east-1:123456789012:parameter/checkout-app/test/payment/events-secret"
  }
}

run "creates_the_api_and_reconcile_functions_on_node_24_arm" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.this["api"].function_name == "checkout-app-test-api" &&
      aws_lambda_function.this["api"].handler == "lambda.handler" &&
      aws_lambda_function.this["api"].memory_size == 1024 &&
      aws_lambda_function.this["api"].timeout == 20
    )
    error_message = "The api function must be <prefix>-api with lambda.handler, 1024 MB and 20 s."
  }

  assert {
    condition = (
      aws_lambda_function.this["reconcile"].handler == "reconcile.handler" &&
      aws_lambda_function.this["reconcile"].memory_size == 512 &&
      aws_lambda_function.this["reconcile"].timeout == 60
    )
    error_message = "The reconcile function must use reconcile.handler, 512 MB and 60 s."
  }

  assert {
    condition = alltrue([
      for function in aws_lambda_function.this :
      function.runtime == "nodejs24.x" && function.architectures == tolist(["arm64"])
    ])
    error_message = "Every function must run on nodejs24.x and arm64."
  }

  assert {
    condition     = alltrue([for alias in aws_lambda_alias.live : alias.name == "live"])
    error_message = "Every function must have the live alias."
  }
}

run "passes_resource_names_but_never_secret_values" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.this["api"].environment[0].variables["APP_ENV"] == "prod" &&
      aws_lambda_function.this["api"].environment[0].variables["TABLE_IDEMPOTENCY"] == "checkout-app-test-idempotency-keys" &&
      aws_lambda_function.this["api"].environment[0].variables["TABLE_TRANSACTION_EVENTS"] == "checkout-app-test-transaction-events" &&
      aws_lambda_function.this["api"].environment[0].variables["PAYMENT_PRIVATE_KEY_PARAM"] == "/checkout-app/test/payment/private-key"
    )
    error_message = "The functions must receive APP_ENV, the table names and the secret parameter names."
  }

  assert {
    condition = alltrue(flatten([
      for function in aws_lambda_function.this : [
        for name in keys(function.environment[0].variables) :
        !startswith(name, "PAYMENT_") || endswith(name, "_PARAM")
      ]
    ]))
    error_message = "Payment provider secrets must be passed as SSM parameter names, never as values."
  }
}

run "logs_are_kept_for_14_days" {
  command = plan

  assert {
    condition = alltrue([
      for group in concat(values(aws_cloudwatch_log_group.function), [aws_cloudwatch_log_group.http_api]) :
      group.retention_in_days == 14
    ])
    error_message = "Every log group must keep logs for 14 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.http_api.name == "/aws/apigateway/checkout-app-test-http"
    error_message = "The access log group must be /aws/apigateway/<prefix>-http."
  }
}

run "iam_follows_least_privilege" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for policy in aws_iam_role_policy.function : [
        for statement in jsondecode(policy.policy).Statement :
        !contains(flatten([statement.Resource]), "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-transaction-events") ||
        length(setintersection(toset(flatten([statement.Action])), toset(["dynamodb:UpdateItem", "dynamodb:DeleteItem"]))) == 0
      ]
    ]))
    error_message = "No function may update or delete audit events."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.function["api"].policy).Statement :
      !contains(flatten([statement.Action]), "dynamodb:Scan") ||
      flatten([statement.Resource]) == ["arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-products"]
    ])
    error_message = "The api may only scan the products table."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.function["api"].policy).Statement :
      !contains(flatten([statement.Action]), "dynamodb:DeleteItem") ||
      flatten([statement.Resource]) == ["arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-idempotency-keys"]
    ])
    error_message = "The api may only delete idempotency keys."
  }

  assert {
    condition = alltrue(flatten([
      for policy in aws_iam_role_policy.function : [
        for statement in jsondecode(policy.policy).Statement :
        !anytrue([for action in flatten([statement.Action]) : startswith(action, "ssm:")]) ||
        toset(flatten([statement.Resource])) == toset(values(var.payment_parameter_arns))
      ]
    ]))
    error_message = "SSM access must be limited to the payment provider secrets."
  }

  assert {
    condition = alltrue(flatten([
      for policy in aws_iam_role_policy.function : [
        for statement in jsondecode(policy.policy).Statement : [
          for resource in flatten([statement.Resource]) : resource != "*"
        ]
      ]
    ]))
    error_message = "No function policy may use wildcard resources."
  }
}

run "http_api_throttles_sensitive_routes" {
  command = plan

  assert {
    condition = toset(keys(aws_apigatewayv2_route.this)) == toset([
      "POST /api/v1/transactions",
      "POST /api/v1/transactions/{id}/payment",
      "POST /api/v1/webhooks/payment-events",
      "ANY /api/{proxy+}",
    ])
    error_message = "The HTTP API must declare the sensitive routes and the /api proxy."
  }

  assert {
    condition = (
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 20 &&
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_burst_limit == 40
    )
    error_message = "The default throttling must be 20 requests per second with a burst of 40."
  }

  assert {
    condition = anytrue([
      for setting in aws_apigatewayv2_stage.default.route_settings :
      setting.route_key == "POST /api/v1/transactions/{id}/payment" &&
      setting.throttling_rate_limit == 5 && setting.throttling_burst_limit == 10
    ])
    error_message = "Payments must be throttled to 5 requests per second with a burst of 10."
  }

  assert {
    condition     = aws_apigatewayv2_integration.api.payload_format_version == "2.0"
    error_message = "The integration must use payload format 2.0."
  }
}

run "api_gateway_only_invokes_the_live_alias" {
  command = apply

  assert {
    condition     = aws_lambda_permission.http_api.qualifier == "live"
    error_message = "API Gateway may only invoke the live alias."
  }

  assert {
    condition     = endswith(aws_lambda_permission.http_api.source_arn, "/*/*")
    error_message = "The permission must be scoped to this HTTP API."
  }
}

run "rejects_unknown_app_env" {
  command = plan

  variables {
    app_env = "staging"
  }

  expect_failures = [var.app_env]
}

run "requires_every_table" {
  command = plan

  variables {
    table_names = { products = "checkout-app-test-products" }
  }

  expect_failures = [var.table_names]
}
