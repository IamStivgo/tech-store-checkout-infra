output "bucket_name" {
  description = "S3 bucket that holds the SPA build and the API docs (api-docs/ prefix)."
  value       = aws_s3_bucket.spa.bucket
}

output "bucket_arn" {
  description = "ARN of the SPA bucket, for the deploy roles."
  value       = aws_s3_bucket.spa.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID, for cache invalidations."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN, for the deploy roles."
  value       = aws_cloudfront_distribution.this.arn
}

output "cloudfront_domain" {
  description = "Public domain of the application (*.cloudfront.net)."
  value       = aws_cloudfront_distribution.this.domain_name
}
