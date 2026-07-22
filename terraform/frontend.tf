# ---------------------------------------------------------------------------
# S3 bucket hosting the static frontend as a public website
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Static websites require public read access; nothing else is exposed
# (no write/delete/list permissions granted to the public).
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "frontend_public_read" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_public_read.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ---------------------------------------------------------------------------
# Frontend assets
# ---------------------------------------------------------------------------
locals {
  frontend_website_origin = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  etag         = filemd5("${path.module}/../frontend/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "style_css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "style.css"
  source       = "${path.module}/../frontend/style.css"
  etag         = filemd5("${path.module}/../frontend/style.css")
  content_type = "text/css"
}

resource "aws_s3_object" "app_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "app.js"
  source       = "${path.module}/../frontend/app.js"
  etag         = filemd5("${path.module}/../frontend/app.js")
  content_type = "application/javascript"
}

# config.js is generated from a template so it always points at the
# currently deployed API Gateway endpoint.
resource "aws_s3_object" "config_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "config.js"
  content      = templatefile("${path.module}/../frontend/config.js.tpl", { api_url = "${aws_apigatewayv2_api.http_api.api_endpoint}/healthcheck" })
  content_type = "application/javascript"
}
