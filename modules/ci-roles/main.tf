locals {
  github_oidc_host = "token.actions.githubusercontent.com"

  # Contract with the web and api pipelines: they read resource names from here instead of
  # hard-coding them. None of these values is secret.
  deploy_parameters = {
    spa-bucket         = var.spa_bucket_name
    distribution-id    = var.distribution_id
    app-url            = var.app_url
    api-function       = var.function_names["api"]
    reconcile-function = var.function_names["reconcile"]
    products-table     = var.products_table_name
  }

  # Only jobs running in the protected production environment of each repository can deploy.
  roles = {
    deploy-web = {
      subject = "repo:${var.web_repository}:environment:production"
      policy  = local.deploy_web_policy
    }
    deploy-api = {
      subject = "repo:${var.api_repository}:environment:production"
      policy  = local.deploy_api_policy
    }
    seed = {
      subject = "repo:${var.api_repository}:environment:production"
      policy  = local.seed_policy
    }
  }
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.github_oidc_host}"
}

# Not secret: insecure_value keeps the values readable in plans.
resource "aws_ssm_parameter" "deploy" {
  for_each = local.deploy_parameters

  name           = "${var.parameter_prefix}/deploy/${each.key}"
  type           = "String"
  insecure_value = each.value
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = "${var.name_prefix}-${each.key}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
            "${local.github_oidc_host}:sub" = each.value.subject
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "this" {
  for_each = local.roles

  name   = "${var.name_prefix}-${each.key}"
  role   = aws_iam_role.this[each.key].id
  policy = jsonencode(each.value.policy)
}
