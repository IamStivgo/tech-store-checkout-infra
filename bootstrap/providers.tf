provider "aws" {
  region = local.aws_region

  default_tags {
    tags = {
      Project     = local.project
      Environment = "shared"
      ManagedBy   = "terraform"
      Repository  = "tech-store-checkout-infra"
    }
  }
}
