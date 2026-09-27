output "role_arns" {
  description = "Deploy role ARNs by purpose (deploy-web, deploy-api, seed), for the GitHub variables of each repository."
  value       = { for key, role in aws_iam_role.this : key => role.arn }
}

output "deploy_parameter_names" {
  description = "SSM parameters read by the pipelines, by logical name."
  value       = { for key, parameter in aws_ssm_parameter.deploy : key => parameter.name }
}
