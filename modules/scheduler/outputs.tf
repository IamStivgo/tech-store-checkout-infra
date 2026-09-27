output "schedule_arn" {
  description = "ARN of the reconciliation schedule."
  value       = aws_scheduler_schedule.reconcile.arn
}
