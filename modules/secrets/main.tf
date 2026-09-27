# The payment provider secrets are SecureString parameters created with the AWS CLI, never
# by Terraform: refreshing an aws_ssm_parameter reads the decrypted value, which would store it
# in the state and fail for the pull request plan role (denied on these paths).

locals {
  secrets = ["private-key", "integrity-secret", "events-secret"]

  parameter_names = {
    for secret in local.secrets : secret => "${var.parameter_prefix}/payment/${secret}"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
