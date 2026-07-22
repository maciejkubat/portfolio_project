output "api_gateway_url" {
  description = "Public URL of the API Gateway endpoint exposing the health-check Lambda."
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/healthcheck"
}

output "frontend_url" {
  description = "Public URL of the static frontend (S3 static website hosting)."
  value       = local.frontend_website_origin
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function."
  value       = aws_lambda_function.healthcheck.function_name
}

output "cloudwatch_alarm_topic_arn" {
  description = "SNS topic ARN used for CloudWatch alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "github_actions_deploy_role_arn" {
  description = "IAM role ARN that GitHub Actions assumes via OIDC to run terraform apply. Set this as the AWS_DEPLOY_ROLE_ARN repository variable/secret."
  value       = aws_iam_role.github_actions_deploy.arn
}

