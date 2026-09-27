terraform {
  # Partial configuration: the bucket is passed with -backend-config="bucket=<state bucket>"
  # so the account ID is not written in the repository.
  backend "s3" {
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
