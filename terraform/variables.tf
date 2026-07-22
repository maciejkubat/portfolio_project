variable "project_name" {
  description = "Project/prefix name used for naming all resources."
  type        = string
  default     = "portfolio-healthcheck"
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile to use (leave null in CI, where credentials come from GitHub Actions OIDC / env vars)."
  type        = string
  default     = null
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, prod)."
  type        = string
  default     = "dev"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds."
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB."
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days."
  type        = number
  default     = 14
}

variable "healthcheck_urls" {
  description = "Comma-separated list of URLs the Lambda function health-checks by default."
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Optional email address subscribed to the CloudWatch alarm SNS topic. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy IAM role via OIDC, in \"owner/repo\" format."
  type        = string
  default     = "maciejkubat/portfolio_project"
}

variable "github_deploy_branch" {
  description = "Git branch allowed to assume the deploy IAM role (restricts OIDC trust to this ref)."
  type        = string
  default     = "main"
}

