locals {
  api_docs_objects = "${var.spa_bucket_arn}/api-docs/*"

  # Qualified ARNs are needed to publish versions and move the live alias.
  function_resources = flatten([for arn in values(var.function_arns) : [arn, "${arn}:*"]])

  read_deploy_parameters = {
    Sid      = "ReadDeployParameters"
    Effect   = "Allow"
    Action   = ["ssm:GetParameter", "ssm:GetParameters"]
    Resource = [for parameter in aws_ssm_parameter.deploy : parameter.arn]
  }

  invalidate_cache = {
    Sid      = "InvalidateCache"
    Effect   = "Allow"
    Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    Resource = var.distribution_arn
  }

  deploy_web_policy = {
    Version = "2012-10-17"
    Statement = [
      local.read_deploy_parameters,
      {
        Sid      = "ListSpaBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.spa_bucket_arn
      },
      {
        Sid      = "SyncSpa"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.spa_bucket_arn}/*"
      },
      {
        # api-docs/ belongs to the api pipeline; a web sync with --delete must never remove it.
        Sid      = "KeepApiDocs"
        Effect   = "Deny"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = local.api_docs_objects
      },
      local.invalidate_cache,
    ]
  }

  deploy_api_policy = {
    Version = "2012-10-17"
    Statement = [
      local.read_deploy_parameters,
      {
        Sid    = "DeployFunctions"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:GetAlias",
          "lambda:UpdateAlias",
        ]
        Resource = local.function_resources
      },
      {
        Sid       = "ListApiDocs"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = var.spa_bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["api-docs/*"] } }
      },
      {
        Sid      = "SyncApiDocs"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = local.api_docs_objects
      },
      local.invalidate_cache,
    ]
  }

  # The seeder only upserts products (UpdateItem without resetting stock).
  seed_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadProductsTableName"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = aws_ssm_parameter.deploy["products-table"].arn
      },
      {
        Sid      = "UpsertProducts"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.products_table_arn
      },
    ]
  }
}
