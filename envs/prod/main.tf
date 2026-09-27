locals {
  project     = "checkout-app"
  environment = "prod"
  aws_region  = "us-east-1"
  name_prefix = "${local.project}-${local.environment}"
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
}

module "scheduler" {
  source = "../../modules/scheduler"

  name_prefix         = local.name_prefix
  target_function_arn = module.api.live_alias_arns["reconcile"]
}
