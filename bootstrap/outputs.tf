output "state_bucket_name" {
  description = "S3 bucket that stores the Terraform state (passed to terraform init with -backend-config)."
  value       = aws_s3_bucket.state.bucket
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "terraform_plan_role_arn" {
  description = "Role assumed by pull request workflows to run terraform plan (read-only)."
  value       = aws_iam_role.terraform["plan"].arn
}

output "terraform_apply_role_arn" {
  description = "Role assumed by the production environment to run terraform apply."
  value       = aws_iam_role.terraform["apply"].arn
}
