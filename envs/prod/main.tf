locals {
  project     = "checkout-app"
  environment = "prod"
  aws_region  = "us-east-1"
  name_prefix = "${local.project}-${local.environment}"
  # GitHub OIDC subjects use immutable IDs: <owner>@<owner_id>/<name>@<repository_id>.
  github_owner = "IamStivgo@94694810"
}

module "database" {
  source = "../../modules/database"

  name_prefix = local.name_prefix
}

module "secrets" {
  source = "../../modules/secrets"

  parameter_prefix = "/${local.project}/${local.environment}"
}

module "api" {
  source = "../../modules/api"

  name_prefix             = local.name_prefix
  app_env                 = local.environment
  placeholder_source_dir  = "${path.root}/../../placeholder"
  table_names             = module.database.table_names
  table_arns              = module.database.table_arns
  payment_parameter_names = module.secrets.parameter_names
  payment_parameter_arns  = module.secrets.parameter_arns
  payment_api_base_url    = var.payment_api_base_url
  payment_public_key      = var.payment_public_key
  origin_verify_secret    = var.origin_verify_secret
}

module "static_site" {
  source = "../../modules/static-site"

  name_prefix = local.name_prefix
  api_domain  = module.api.http_api_domain

  origin_verify_secret = var.origin_verify_secret
  # The browser tokenizes the card directly with the payment provider.
  csp_connect_origins = [regex("^https://[^/]+", var.payment_api_base_url)]
}

module "scheduler" {
  source = "../../modules/scheduler"

  name_prefix         = local.name_prefix
  target_function_arn = module.api.live_alias_arns["reconcile"]
}

module "ci_roles" {
  source = "../../modules/ci-roles"

  name_prefix         = local.name_prefix
  parameter_prefix    = "/${local.project}/${local.environment}"
  web_repository      = "${local.github_owner}/tech-store-checkout-web@1388345025"
  api_repository      = "${local.github_owner}/tech-store-checkout-api@1388345462"
  spa_bucket_name     = module.static_site.bucket_name
  spa_bucket_arn      = module.static_site.bucket_arn
  distribution_id     = module.static_site.distribution_id
  distribution_arn    = module.static_site.distribution_arn
  app_url             = "https://${module.static_site.cloudfront_domain}"
  function_names      = module.api.function_names
  function_arns       = module.api.function_arns
  products_table_name = module.database.table_names["products"]
  products_table_arn  = module.database.table_arns["products"]
}
