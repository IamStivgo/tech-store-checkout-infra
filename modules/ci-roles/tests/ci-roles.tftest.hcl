mock_provider "aws" {
  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
}

variables {
  name_prefix         = "checkout-app-test"
  parameter_prefix    = "/checkout-app/test"
  web_repository      = "octo-org/web-repo"
  api_repository      = "octo-org/api-repo"
  spa_bucket_name     = "checkout-app-test-spa-123456789012"
  spa_bucket_arn      = "arn:aws:s3:::checkout-app-test-spa-123456789012"
  distribution_id     = "E2TESTDISTRIBUTION"
  distribution_arn    = "arn:aws:cloudfront::123456789012:distribution/E2TESTDISTRIBUTION"
  app_url             = "https://d111111abcdef8.cloudfront.net"
  products_table_name = "checkout-app-test-products"
  products_table_arn  = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-products"

  function_names = {
    api       = "checkout-app-test-api"
    reconcile = "checkout-app-test-reconcile"
  }

  function_arns = {
    api       = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-api"
    reconcile = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-reconcile"
  }
}

run "publishes_the_deploy_contract_as_plain_parameters" {
  command = plan

  assert {
    condition = {
      for key, parameter in aws_ssm_parameter.deploy : key => parameter.name
      } == {
      spa-bucket         = "/checkout-app/test/deploy/spa-bucket"
      distribution-id    = "/checkout-app/test/deploy/distribution-id"
      app-url            = "/checkout-app/test/deploy/app-url"
      api-function       = "/checkout-app/test/deploy/api-function"
      reconcile-function = "/checkout-app/test/deploy/reconcile-function"
      products-table     = "/checkout-app/test/deploy/products-table"
    }
    error_message = "The deploy parameters must live under <prefix>/deploy/."
  }

  assert {
    condition     = alltrue([for parameter in aws_ssm_parameter.deploy : parameter.type == "String"])
    error_message = "Deploy parameters are not secret and must be plain strings."
  }

  assert {
    condition     = aws_ssm_parameter.deploy["distribution-id"].insecure_value == "E2TESTDISTRIBUTION"
    error_message = "Parameters must hold the resource names of the environment."
  }
}

run "each_role_trusts_the_production_environment_of_its_repository" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.this)) == toset(["deploy-web", "deploy-api", "seed"])
    error_message = "The module must create the deploy-web, deploy-api and seed roles."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.this["deploy-web"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:octo-org/web-repo:environment:production"
    )
    error_message = "deploy-web must only trust the production environment of the web repository."
  }

  assert {
    condition = alltrue([
      for role in ["deploy-api", "seed"] :
      jsondecode(aws_iam_role.this[role].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:octo-org/api-repo:environment:production"
    ])
    error_message = "deploy-api and seed must only trust the production environment of the api repository."
  }

  assert {
    condition = alltrue([
      for role in aws_iam_role.this :
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    ])
    error_message = "Every role must require the sts.amazonaws.com audience."
  }
}

run "web_and_api_deploys_own_separate_parts_of_the_bucket" {
  command = apply

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.this["deploy-web"].policy).Statement :
      statement.Effect == "Deny" &&
      statement.Resource == "arn:aws:s3:::checkout-app-test-spa-123456789012/api-docs/*" &&
      contains(statement.Action, "s3:DeleteObject")
    ])
    error_message = "The web deploy must never write or delete api-docs/."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.this["deploy-api"].policy).Statement :
      statement.Resource == "arn:aws:s3:::checkout-app-test-spa-123456789012/api-docs/*"
      if anytrue([for action in flatten([statement.Action]) : contains(["s3:PutObject", "s3:DeleteObject"], action)])
    ])
    error_message = "The api deploy may only write api-docs/."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.this["deploy-api"].policy).Statement :
      statement.Sid == "DeployFunctions" &&
      contains(statement.Resource, "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-api:*")
    ])
    error_message = "The api deploy must be able to publish versions and move the live alias."
  }
}

run "seed_only_upserts_products" {
  command = apply

  assert {
    condition = [
      for statement in jsondecode(aws_iam_role_policy.this["seed"].policy).Statement :
      { action = statement.Action, resource = statement.Resource }
      if startswith(flatten([statement.Action])[0], "dynamodb:")
      ] == [
      { action = "dynamodb:UpdateItem", resource = "arn:aws:dynamodb:us-east-1:123456789012:table/checkout-app-test-products" },
    ]
    error_message = "The seed role may only update items of the products table."
  }
}

run "no_role_uses_wildcards" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for policy in aws_iam_role_policy.this : [
        for statement in jsondecode(policy.policy).Statement : [
          for value in concat(flatten([statement.Action]), flatten([statement.Resource])) :
          value != "*" && !endswith(value, ":*:*")
        ]
      ]
    ]))
    error_message = "Deploy roles must name their actions and resources."
  }
}

run "rejects_invalid_app_urls" {
  command = plan

  variables {
    app_url = "http://d111111abcdef8.cloudfront.net/"
  }

  expect_failures = [var.app_url]
}
