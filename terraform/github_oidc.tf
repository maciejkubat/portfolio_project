# ---------------------------------------------------------------------------
# GitHub Actions OIDC federation - lets the "deploy.yml" workflow assume an
# AWS IAM role without any long-lived AWS access keys stored in GitHub.
# ---------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# Trust policy: only the configured repository, and only when the workflow
# runs on the configured branch (refs/heads/<github_deploy_branch>), may
# assume this role. This prevents forks or other branches/PRs from deploying.
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_deploy_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${var.project_name}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# Permissions required for `terraform plan`/`apply` to manage exactly the
# resources declared in this project (state backend, Lambda, API Gateway,
# CloudWatch, SNS, IAM role/policy for the Lambda, S3 frontend bucket).
# Scoped by resource name prefix/ARN rather than "*" wherever the AWS API
# allows it.
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "TerraformStateBackend"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.tfstate_lock.arn]
  }

  statement {
    sid    = "ManageFrontendBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketWebsite",
      "s3:PutBucketWebsite",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:CreateBucket",
      "s3:DeleteBucket",
    ]
    resources = [
      aws_s3_bucket.frontend.arn,
      "${aws_s3_bucket.frontend.arn}/*",
      "arn:aws:s3:::${var.project_name}-frontend",
      "arn:aws:s3:::${var.project_name}-frontend/*",
    ]
  }

  statement {
    sid    = "ManageLambda"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:GetPolicy",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
    ]
    resources = ["arn:aws:lambda:${var.aws_region}:*:function:${var.project_name}-*"]
  }

  statement {
    sid    = "ManageLambdaExecutionRole"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::*:role/${var.project_name}-*"]
  }

  statement {
    sid    = "ManageOidcProvider"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
    ]
    resources = ["arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com"]
  }

  statement {
    sid    = "ManageApiGateway"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
    ]
    resources = ["arn:aws:apigateway:${var.aws_region}::*"]
  }

  statement {
    sid    = "ManageCloudWatchAndSns"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DescribeLogGroups",
      "logs:TagResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:TagResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "${var.project_name}-gha-deploy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
