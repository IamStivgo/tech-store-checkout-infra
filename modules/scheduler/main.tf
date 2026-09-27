data "aws_caller_identity" "current" {}

resource "aws_iam_role" "scheduler" {
  name = "${var.name_prefix}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "scheduler.amazonaws.com" }
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "invoke_reconcile" {
  name = "${var.name_prefix}-scheduler"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeReconcile"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = var.target_function_arn
      },
    ]
  })
}

resource "aws_scheduler_schedule" "reconcile" {
  name                = "${var.name_prefix}-reconcile"
  group_name          = "default"
  schedule_expression = var.schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.target_function_arn
    role_arn = aws_iam_role.scheduler.arn

    # A run older than the interval is useless: the next one covers the same work.
    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 300
    }
  }
}
