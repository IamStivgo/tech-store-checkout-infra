locals {
  # Every project resource is named checkout-app-*, so permissions are scoped by name prefix
  # wherever the service supports resource-level permissions.
  project_arns = {
    tables     = "arn:aws:dynamodb:${local.aws_region}:${local.account_id}:table/${local.project}-*"
    functions  = "arn:aws:lambda:${local.aws_region}:${local.account_id}:function:${local.project}-*"
    buckets    = "arn:aws:s3:::${local.project}-*"
    parameters = "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter/${local.project}/*"
    schedules  = "arn:aws:scheduler:${local.aws_region}:${local.account_id}:schedule/*/${local.project}-*"
    log_groups = [
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.project}-*",
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:/aws/apigateway/${local.project}-*",
    ]
    iam = [
      "arn:aws:iam::${local.account_id}:role/${local.project}-*",
      "arn:aws:iam::${local.account_id}:policy/${local.project}-*",
    ]
  }

  # Payment provider secrets are loaded outside Terraform; pull requests must never read them.
  payment_secret_arns = "arn:aws:ssm:${local.aws_region}:${local.account_id}:parameter/${local.project}/*/payment/*"

  # Resources created here that the Terraform roles must not be able to change.
  bootstrap_iam_arns = [
    "arn:aws:iam::${local.account_id}:role/${local.project}-terraform-*",
    aws_iam_openid_connect_provider.github.arn,
  ]

  account_listings = [
    "dynamodb:ListTables",
    "lambda:ListFunctions",
    "lambda:GetAccountSettings",
    "s3:ListAllMyBuckets",
    "ssm:DescribeParameters",
    "logs:DescribeLogGroups",
    "logs:DescribeResourcePolicies",
    "logs:GetLogDelivery",
    "logs:ListLogDeliveries",
    "scheduler:ListSchedules",
    "iam:ListRoles",
    "iam:ListPolicies",
    "iam:ListOpenIDConnectProviders",
    "sts:GetCallerIdentity",
  ]

  plan_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadProjectResources"
        Effect = "Allow"
        Action = [
          "dynamodb:Describe*",
          "dynamodb:ListTagsOfResource",
          "lambda:Get*",
          "lambda:List*",
          "s3:Get*",
          "s3:List*",
          "ssm:GetParameter*",
          "ssm:ListTagsForResource",
          "scheduler:Get*",
          "scheduler:ListTagsForResource",
          "logs:ListTagsForResource",
          "logs:ListTagsLogGroup",
          "iam:Get*",
          "iam:List*",
        ]
        Resource = flatten([
          local.project_arns.tables,
          local.project_arns.functions,
          local.project_arns.buckets,
          "${local.project_arns.buckets}/*",
          local.project_arns.parameters,
          local.project_arns.schedules,
          local.project_arns.log_groups,
          local.project_arns.iam,
          aws_iam_openid_connect_provider.github.arn,
        ])
      },
      {
        Sid      = "ReadServicesWithoutNameScopedResources"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "cloudfront:Get*", "cloudfront:List*", "cloudfront:Describe*"]
        Resource = "*"
      },
      {
        Sid      = "ReadAccountListings"
        Effect   = "Allow"
        Action   = local.account_listings
        Resource = "*"
      },
      {
        # terraform plan takes the S3 native lock.
        Sid      = "LockTerraformState"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/*.tflock"
      },
      {
        Sid      = "DenyPaymentSecrets"
        Effect   = "Deny"
        Action   = "ssm:GetParameter*"
        Resource = local.payment_secret_arns
      },
    ]
  }

  apply_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageProjectResources"
        Effect = "Allow"
        Action = ["dynamodb:*", "lambda:*", "s3:*", "ssm:*", "scheduler:*", "logs:*", "iam:*"]
        Resource = flatten([
          local.project_arns.tables,
          local.project_arns.functions,
          local.project_arns.buckets,
          "${local.project_arns.buckets}/*",
          local.project_arns.parameters,
          local.project_arns.schedules,
          local.project_arns.log_groups,
          local.project_arns.iam,
        ])
      },
      {
        # The deploy roles for the web and api repositories trust this provider.
        Sid      = "ReadGitHubOidcProvider"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider"]
        Resource = aws_iam_openid_connect_provider.github.arn
      },
      {
        Sid      = "ManageServicesWithoutNameScopedResources"
        Effect   = "Allow"
        Action   = ["apigateway:*", "cloudfront:*"]
        Resource = "*"
      },
      {
        Sid    = "AccountListingsAndLogDelivery"
        Effect = "Allow"
        Action = concat(local.account_listings, [
          "logs:CreateLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:PutResourcePolicy",
        ])
        Resource = "*"
      },
      {
        Sid    = "ProtectBootstrapIdentities"
        Effect = "Deny"
        Action = [
          "iam:Add*",
          "iam:Attach*",
          "iam:Create*",
          "iam:Delete*",
          "iam:Detach*",
          "iam:Put*",
          "iam:Remove*",
          "iam:Tag*",
          "iam:Untag*",
          "iam:Update*",
        ]
        Resource = local.bootstrap_iam_arns
      },
      {
        Sid      = "ProtectStateBucket"
        Effect   = "Deny"
        Action   = ["s3:DeleteBucket*", "s3:PutBucket*", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "ProtectStateHistory"
        Effect   = "Deny"
        Action   = "s3:DeleteObjectVersion"
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
      {
        Sid      = "DenyBroadManagedPolicies"
        Effect   = "Deny"
        Action   = ["iam:AttachRolePolicy"]
        Resource = "*"
        Condition = {
          ArnLike = {
            "iam:PolicyARN" = [
              "arn:aws:iam::aws:policy/AdministratorAccess",
              "arn:aws:iam::aws:policy/PowerUserAccess",
              "arn:aws:iam::aws:policy/IAMFullAccess",
            ]
          }
        }
      },
      {
        Sid    = "DenyCostlyFeatures"
        Effect = "Deny"
        Action = [
          "lambda:PutProvisionedConcurrencyConfig",
          "dynamodb:CreateTableReplica",
          "dynamodb:CreateGlobalTable",
          "dynamodb:UpdateGlobalTable",
          "dynamodb:UpdateGlobalTableSettings",
          "dynamodb:EnableKinesisStreamingDestination",
          "dynamodb:ExportTableToPointInTime",
          "s3:PutAccelerateConfiguration",
          "s3:PutReplicationConfiguration",
          "cloudfront:CreateRealtimeLogConfig",
        ]
        Resource = "*"
      },
    ]
  }
}
