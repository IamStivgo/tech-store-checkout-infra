locals {
  default_throttling = { rate = 20, burst = 40 }

  # Sensitive routes are declared explicitly so they can be throttled apart from the proxy.
  routes = {
    "POST /api/v1/transactions"              = { rate = 5, burst = 10 }
    "POST /api/v1/transactions/{id}/payment" = { rate = 5, burst = 10 }
    "POST /api/v1/webhooks/payment-events"   = { rate = 10, burst = 20 }
    "ANY /api/{proxy+}"                      = null
  }

  throttled_routes = { for route, limits in local.routes : route => limits if limits != null }
}

resource "aws_cloudwatch_log_group" "http_api" {
  name              = "/aws/apigateway/${var.name_prefix}-http"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.name_prefix}-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live["api"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.http.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = local.default_throttling.rate
    throttling_burst_limit = local.default_throttling.burst
  }

  dynamic "route_settings" {
    for_each = local.throttled_routes

    content {
      route_key              = route_settings.key
      throttling_rate_limit  = route_settings.value.rate
      throttling_burst_limit = route_settings.value.burst
    }
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.http_api.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      routeKey           = "$context.routeKey"
      path               = "$context.path"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      responseLatency    = "$context.responseLatency"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
    })
  }

  # Route settings can only reference routes that already exist.
  depends_on = [aws_apigatewayv2_route.this]
}

resource "aws_lambda_permission" "http_api" {
  statement_id  = "AllowHttpApiInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["api"].function_name
  qualifier     = aws_lambda_alias.live["api"].name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
