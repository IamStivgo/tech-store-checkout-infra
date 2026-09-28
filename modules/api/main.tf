locals {
  functions = {
    api = {
      handler     = "lambda.handler"
      memory_size = 1024
      timeout     = 20
    }
    reconcile = {
      handler     = "reconcile.handler"
      memory_size = 512
      timeout     = 60
    }
  }

  table_env_vars = {
    products           = "TABLE_PRODUCTS"
    customers          = "TABLE_CUSTOMERS"
    transactions       = "TABLE_TRANSACTIONS"
    deliveries         = "TABLE_DELIVERIES"
    idempotency-keys   = "TABLE_IDEMPOTENCY"
    transaction-events = "TABLE_TRANSACTION_EVENTS"
  }

  environment_variables = merge(
    {
      APP_ENV              = var.app_env
      LOG_LEVEL            = var.log_level
      PAYMENT_PROVIDER     = "http"
      PAYMENT_API_BASE_URL = var.payment_api_base_url
      PAYMENT_PUBLIC_KEY   = var.payment_public_key
    },
    { for table, env_var in local.table_env_vars : env_var => var.table_names[table] },
    {
      for secret, name in var.payment_parameter_names :
      "PAYMENT_${upper(replace(secret, "-", "_"))}_PARAM" => name
    },
  )
}

data "archive_file" "placeholder" {
  type        = "zip"
  source_dir  = var.placeholder_source_dir
  output_path = "${path.root}/.build/placeholder.zip"
}

resource "aws_cloudwatch_log_group" "function" {
  for_each = local.functions

  name              = "/aws/lambda/${var.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "function" {
  for_each = local.functions

  name = "${var.name_prefix}-${each.key}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "lambda.amazonaws.com" }
      },
    ]
  })
}

resource "aws_iam_role_policy" "function" {
  for_each = local.functions

  name   = "${var.name_prefix}-${each.key}-lambda"
  role   = aws_iam_role.function[each.key].id
  policy = jsonencode(local.function_policies[each.key])
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name = "${var.name_prefix}-${each.key}"
  role          = aws_iam_role.function[each.key].arn
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  handler       = each.value.handler
  memory_size   = each.value.memory_size
  timeout       = each.value.timeout

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = local.environment_variables
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.function[each.key].name
  }

  # The api repository deploys the code; Terraform owns configuration and permissions.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_iam_role_policy.function]
}

# API Gateway and the scheduler invoke this alias; the api deployment publishes a version
# and moves the alias to it, so a rollback is just moving it back.
resource "aws_lambda_alias" "live" {
  for_each = local.functions

  name             = "live"
  function_name    = aws_lambda_function.this[each.key].function_name
  function_version = "$LATEST"

  lifecycle {
    ignore_changes = [function_version]
  }
}
