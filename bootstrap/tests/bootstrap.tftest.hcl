mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::checkout-app-tfstate-123456789012"
    }
  }
}

variables {
  github_repository = "octo-org/infra-repo"
}

run "state_bucket_is_unique_versioned_encrypted_and_private" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "checkout-app-tfstate-123456789012"
    error_message = "The state bucket must be named checkout-app-tfstate-<account_id>."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "The state bucket must be versioned."
  }

  assert {
    condition = one([
      for rule in aws_s3_bucket_server_side_encryption_configuration.state.rule :
      rule.apply_server_side_encryption_by_default[0].sse_algorithm
    ]) == "AES256"
    error_message = "The state bucket must be encrypted with SSE-S3."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "The state bucket must block every form of public access."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "The state bucket must disable ACLs."
  }
}

run "state_bucket_only_accepts_tls" {
  command = apply

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.state.policy).Statement :
      statement.Effect == "Deny" && try(statement.Condition.Bool["aws:SecureTransport"], "") == "false"
    ])
    error_message = "The state bucket policy must deny requests without TLS."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.state.policy).Statement :
      statement.Effect == "Deny" && try(statement.Condition.NumericLessThan["s3:TlsVersion"], "") == "1.2"
    ])
    error_message = "The state bucket policy must deny TLS versions older than 1.2."
  }
}

run "old_state_versions_expire" {
  command = apply

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.state.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Noncurrent state versions must expire after 90 days."
  }
}

run "oidc_provider_trusts_github_actions_for_sts" {
  command = apply

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "The OIDC provider must be GitHub Actions."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The OIDC provider audience must be sts.amazonaws.com."
  }
}

run "each_role_trusts_a_single_subject_of_the_repository" {
  command = apply

  assert {
    condition     = toset(keys(aws_iam_role.terraform)) == toset(["plan", "apply"])
    error_message = "The bootstrap must create exactly the plan and apply roles."
  }

  assert {
    condition     = aws_iam_role.terraform["plan"].name == "checkout-app-terraform-plan"
    error_message = "Role names must be checkout-app-terraform-<purpose>."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.terraform["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:octo-org/infra-repo:pull_request"
    )
    error_message = "The plan role must only trust pull requests of the repository."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.terraform["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
      == "repo:octo-org/infra-repo:environment:production"
    )
    error_message = "The apply role must only trust the production environment of the repository."
  }

  assert {
    condition = alltrue([
      for role in aws_iam_role.terraform :
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    ])
    error_message = "Every role must require the sts.amazonaws.com audience."
  }
}

run "plan_role_is_read_only" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(aws_iam_role_policy.terraform["plan"].policy).Statement : [
        for action in flatten([statement.Action]) :
        can(regex("^[a-z0-9]+:(Get|List|Describe)", action)) || action == "apigateway:GET" || action == "sts:GetCallerIdentity"
      ] if statement.Effect == "Allow" && statement.Sid != "LockTerraformState"
    ]))
    error_message = "The plan role may only read, apart from the state lock."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_role_policy.terraform["plan"].policy).Statement :
      statement.Resource if statement.Sid == "LockTerraformState"
    ]) == "arn:aws:s3:::checkout-app-tfstate-123456789012/*.tflock"
    error_message = "The plan role may only write the state lock files."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.terraform["plan"].policy).Statement :
      statement.Effect == "Deny" && statement.Action == "ssm:GetParameter*" &&
      statement.Resource == "arn:aws:ssm:us-east-1:123456789012:parameter/checkout-app/*/payment/*"
    ])
    error_message = "The plan role must never read the payment provider secrets."
  }
}

run "apply_role_cannot_change_the_bootstrap" {
  command = apply

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.terraform["apply"].policy).Statement :
      statement.Effect == "Deny" && contains(flatten([statement.Action]), "iam:Put*") &&
      contains(flatten([statement.Resource]), "arn:aws:iam::123456789012:role/checkout-app-terraform-*")
    ])
    error_message = "The apply role must not modify the Terraform roles."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.terraform["apply"].policy).Statement :
      statement.Effect == "Deny" && contains(flatten([statement.Action]), "s3:PutBucket*") &&
      statement.Resource == "arn:aws:s3:::checkout-app-tfstate-123456789012"
    ])
    error_message = "The apply role must not reconfigure the state bucket."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.terraform["apply"].policy).Statement :
      alltrue([for resource in flatten([statement.Resource]) : resource != "*"])
      if statement.Effect == "Allow" && statement.Sid != "ManageServicesWithoutNameScopedResources" && statement.Sid != "AccountListingsAndLogDelivery"
    ])
    error_message = "Apart from services without resource-level permissions, the apply role must be scoped by name prefix."
  }
}

run "rejects_invalid_repositories" {
  command = plan

  variables {
    github_repository = "not a repository"
  }

  expect_failures = [var.github_repository]
}
