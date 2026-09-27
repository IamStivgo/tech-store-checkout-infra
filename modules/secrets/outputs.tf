output "parameter_names" {
  description = "SSM parameter names of the payment provider secrets by logical name (private-key, integrity-secret, events-secret)."
  value       = local.parameter_names
}

output "parameter_arns" {
  description = "SSM parameter ARNs of the payment provider secrets by logical name, for IAM policies."
  value = {
    for secret, name in local.parameter_names :
    secret => "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${name}"
  }
}
