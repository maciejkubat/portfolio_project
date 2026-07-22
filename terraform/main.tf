terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  function_name = "${var.project_name}-healthcheck"
}

# Package the existing Lambda source (app/app.py) into a zip archive.
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../app/app.py"
  output_path = "${path.module}/build/lambda_package.zip"
}
