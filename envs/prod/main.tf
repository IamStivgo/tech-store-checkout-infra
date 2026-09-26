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
