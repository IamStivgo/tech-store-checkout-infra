mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::checkout-app-test-spa-123456789012"
      bucket_regional_domain_name = "checkout-app-test-spa-123456789012.s3.us-east-1.amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E2TESTDISTRIBUTION"
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/checkout-app-test-spa-router"
    }
  }
}

variables {
  name_prefix = "checkout-app-test"
  api_domain  = "abc123.execute-api.us-east-1.amazonaws.com"
}

run "spa_bucket_is_private_and_only_readable_by_the_distribution" {
  command = apply

  assert {
    condition     = aws_s3_bucket.spa.bucket == "checkout-app-test-spa-123456789012"
    error_message = "The SPA bucket must be named <prefix>-spa-<account_id>."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.spa.block_public_acls,
      aws_s3_bucket_public_access_block.spa.block_public_policy,
      aws_s3_bucket_public_access_block.spa.ignore_public_acls,
      aws_s3_bucket_public_access_block.spa.restrict_public_buckets,
    ])
    error_message = "The SPA bucket must block every form of public access."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.spa.policy).Statement :
      statement.Effect == "Allow" &&
      statement.Principal == { Service = "cloudfront.amazonaws.com" } &&
      statement.Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::123456789012:distribution/E2TESTDISTRIBUTION"
    ])
    error_message = "Only this distribution may read the bucket (OAC with AWS:SourceArn)."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.spa.policy).Statement :
      statement.Effect == "Deny" && try(statement.Condition.Bool["aws:SecureTransport"], "") == "false"
    ])
    error_message = "The SPA bucket must deny requests without TLS."
  }
}

run "api_errors_are_never_replaced_by_the_spa" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "The distribution must not use custom error responses."
  }

  assert {
    condition = one([
      for behavior in aws_cloudfront_distribution.this.default_cache_behavior[0].function_association :
      behavior.event_type
    ]) == "viewer-request"
    error_message = "SPA routing must be done by the viewer-request function."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.spa_router.code, "request.uri = '/index.html'")
    error_message = "The spa-router function must rewrite extensionless paths to /index.html."
  }
}

run "api_behavior_forwards_everything_and_caches_nothing" {
  command = plan

  assert {
    condition = anytrue([
      for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior :
      behavior.path_pattern == "/api/*" &&
      behavior.target_origin_id == "api" &&
      behavior.viewer_protocol_policy == "https-only" &&
      contains(behavior.allowed_methods, "POST") &&
      behavior.response_headers_policy_id == null
    ])
    error_message = "/api/* must go to API Gateway over HTTPS, allow every method and add no headers policy."
  }

  assert {
    condition = anytrue([
      for origin in aws_cloudfront_distribution.this.origin :
      origin.origin_id == "api" &&
      origin.domain_name == "abc123.execute-api.us-east-1.amazonaws.com" &&
      origin.custom_origin_config[0].origin_protocol_policy == "https-only" &&
      origin.custom_origin_config[0].origin_ssl_protocols == toset(["TLSv1.2"])
    ])
    error_message = "The API origin must be reached only over TLS 1.2."
  }
}

run "security_headers_follow_the_design" {
  command = plan

  assert {
    condition = (
      aws_cloudfront_response_headers_policy.this["spa"].security_headers_config[0].content_security_policy[0].content_security_policy ==
      "default-src 'none'; script-src 'self'; img-src 'self' data:; font-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'; upgrade-insecure-requests; style-src 'self'; connect-src 'self'"
    )
    error_message = "The SPA CSP must match security-design §6.3."
  }

  assert {
    condition = (
      aws_cloudfront_response_headers_policy.this["spa"].security_headers_config[0].strict_transport_security[0].access_control_max_age_sec == 63072000 &&
      !aws_cloudfront_response_headers_policy.this["spa"].security_headers_config[0].strict_transport_security[0].preload
    )
    error_message = "HSTS must last two years, without preload."
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.this["spa"].security_headers_config[0].frame_options[0].frame_option == "DENY"
    error_message = "The SPA must not be framed."
  }

  assert {
    condition = toset([
      for header in aws_cloudfront_response_headers_policy.this["spa"].custom_headers_config[0].items : header.header
    ]) == toset(["Permissions-Policy", "Cross-Origin-Opener-Policy", "Cross-Origin-Resource-Policy"])
    error_message = "The SPA must send Permissions-Policy, COOP and CORP."
  }

  assert {
    condition     = strcontains(aws_cloudfront_response_headers_policy.this["api-docs"].security_headers_config[0].content_security_policy[0].content_security_policy, "style-src 'self' 'unsafe-inline'")
    error_message = "Swagger UI needs inline styles in its own policy."
  }
}

run "connect_src_accepts_extra_origins" {
  command = plan

  variables {
    csp_connect_origins = ["https://sandbox.payments.example"]
  }

  assert {
    condition     = strcontains(aws_cloudfront_response_headers_policy.this["spa"].security_headers_config[0].content_security_policy[0].content_security_policy, "connect-src 'self' https://sandbox.payments.example")
    error_message = "Extra origins must be appended to connect-src."
  }
}

run "rejects_api_domains_with_scheme" {
  command = plan

  variables {
    api_domain = "https://abc123.execute-api.us-east-1.amazonaws.com"
  }

  expect_failures = [var.api_domain]
}

run "rejects_insecure_connect_origins" {
  command = plan

  variables {
    csp_connect_origins = ["http://sandbox.payments.example"]
  }

  expect_failures = [var.csp_connect_origins]
}
