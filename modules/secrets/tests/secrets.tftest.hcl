mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  parameter_prefix = "/checkout-app/test"
}

run "names_the_three_payment_secrets_under_the_prefix" {
  command = plan

  assert {
    condition = output.parameter_names == {
      "private-key"      = "/checkout-app/test/payment/private-key"
      "integrity-secret" = "/checkout-app/test/payment/integrity-secret"
      "events-secret"    = "/checkout-app/test/payment/events-secret"
    }
    error_message = "The module must name the three payment secrets as <prefix>/payment/<secret>."
  }
}

run "builds_the_arns_for_iam_policies" {
  command = plan

  assert {
    condition     = output.parameter_arns["private-key"] == "arn:aws:ssm:us-east-1:123456789012:parameter/checkout-app/test/payment/private-key"
    error_message = "Parameter ARNs must be arn:aws:ssm:<region>:<account>:parameter<name>."
  }

  assert {
    condition     = toset(keys(output.parameter_arns)) == toset(keys(output.parameter_names))
    error_message = "Every parameter name must have its ARN."
  }
}

run "rejects_prefixes_with_a_trailing_slash" {
  command = plan

  variables {
    parameter_prefix = "/checkout-app/prod/"
  }

  expect_failures = [var.parameter_prefix]
}

run "rejects_relative_prefixes" {
  command = plan

  variables {
    parameter_prefix = "checkout-app/prod"
  }

  expect_failures = [var.parameter_prefix]
}
