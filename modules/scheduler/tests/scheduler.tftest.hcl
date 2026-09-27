mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/checkout-app-test-scheduler"
    }
  }
}

variables {
  name_prefix         = "checkout-app-test"
  target_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-reconcile:live"
}

run "runs_reconciliation_every_five_minutes_on_the_live_alias" {
  command = apply

  assert {
    condition     = aws_scheduler_schedule.reconcile.name == "checkout-app-test-reconcile"
    error_message = "The schedule must be named <prefix>-reconcile."
  }

  assert {
    condition     = aws_scheduler_schedule.reconcile.schedule_expression == "rate(5 minutes)"
    error_message = "Reconciliation must run every five minutes by default."
  }

  assert {
    condition     = aws_scheduler_schedule.reconcile.flexible_time_window[0].mode == "OFF"
    error_message = "The schedule must not use a flexible time window."
  }

  assert {
    condition     = aws_scheduler_schedule.reconcile.target[0].arn == var.target_function_arn
    error_message = "The schedule must invoke the live alias of reconcile."
  }
}

run "stale_runs_are_not_retried" {
  command = apply

  assert {
    condition = (
      aws_scheduler_schedule.reconcile.target[0].retry_policy[0].maximum_retry_attempts == 2 &&
      aws_scheduler_schedule.reconcile.target[0].retry_policy[0].maximum_event_age_in_seconds == 300
    )
    error_message = "Retries must stop after 2 attempts or 5 minutes."
  }
}

run "role_can_only_invoke_the_target" {
  command = apply

  assert {
    condition = (
      jsondecode(aws_iam_role.scheduler.assume_role_policy).Statement[0].Principal.Service == "scheduler.amazonaws.com" &&
      jsondecode(aws_iam_role.scheduler.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "Only the scheduler of this account may assume the role."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.invoke_reconcile.policy).Statement == [
      {
        Sid      = "InvokeReconcile"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-reconcile:live"
      },
    ]
    error_message = "The role may only invoke the target alias."
  }
}

run "rejects_unqualified_function_arns" {
  command = plan

  variables {
    target_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:checkout-app-test-reconcile"
  }

  expect_failures = [var.target_function_arn]
}

run "rejects_invalid_expressions" {
  command = plan

  variables {
    schedule_expression = "every 5 minutes"
  }

  expect_failures = [var.schedule_expression]
}
