locals {
  project    = "checkout-app"
  aws_region = "us-east-1"
  account_id = data.aws_caller_identity.current.account_id

  github_oidc_host = "token.actions.githubusercontent.com"

  # Each role trusts exactly one OIDC subject: pull requests can only plan, and only
  # jobs in the protected production environment can apply.
  terraform_roles = {
    plan = {
      description = "Runs terraform plan from pull requests (read-only)."
      subject     = "repo:${var.github_repository}:pull_request"
      policy      = local.plan_policy
    }
    apply = {
      description = "Runs terraform apply from the production environment."
      subject     = "repo:${var.github_repository}:environment:production"
      policy      = local.apply_policy
    }
  }
}

data "aws_caller_identity" "current" {}

# Terraform state

resource "aws_s3_bucket" "state" {
  # The account ID keeps the global bucket name unique without writing it in the repository.
  bucket = "${local.project}-tfstate-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyOutdatedTls"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
        Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# GitHub Actions federation

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "terraform" {
  for_each = local.terraform_roles

  name                 = "${local.project}-terraform-${each.key}"
  description          = each.value.description
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
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

resource "aws_iam_role_policy" "terraform" {
  for_each = local.terraform_roles

  name   = "${local.project}-terraform-${each.key}"
  role   = aws_iam_role.terraform[each.key].id
  policy = jsonencode(each.value.policy)
}
