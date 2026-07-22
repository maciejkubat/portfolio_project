# ---------------------------------------------------------------------------
# IAM: least-privilege execution role for the Lambda function
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Only allow writing logs to this function's own CloudWatch log group -
# no wildcard resources, no extra AWS API permissions (the function only
# performs outbound HTTP calls, which require no IAM permissions).
data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name   = "${local.function_name}-logging"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_logging.json
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "healthcheck" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      HEALTHCHECK_URLS = var.healthcheck_urls
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logging,
    aws_cloudwatch_log_group.lambda,
  ]
}

# ---------------------------------------------------------------------------
# API Gateway (HTTP API) - public endpoint in front of the Lambda function
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${local.function_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [local.frontend_website_origin]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.healthcheck.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "healthcheck" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /healthcheck"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.healthcheck.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
