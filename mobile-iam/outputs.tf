output "mobile_ci_role_arn" {
  description = "ARN of the mobile-ci IAM role — store as repo secret AWS_OIDC_ROLE_ARN_MOBILE_CI"
  value       = aws_iam_role.mobile_ci.arn
}

output "mobile_release_role_arn" {
  description = "ARN of the mobile-release IAM role — store as mobile-release env secret AWS_OIDC_ROLE_ARN_MOBILE_RELEASE"
  value       = aws_iam_role.mobile_release.arn
}
