/*
  Remote state backend: S3 bucket (state storage) + DynamoDB table (state locking).

  NOTE - chicken-and-egg problem:
  Terraform cannot create the S3 bucket / DynamoDB table referenced by its own
  `backend "s3" {}` block in the same `terraform init` run that also configures
  that backend. Recommended two-step bootstrap:

    1. Leave the `backend "s3" {}` block below commented out, run
       `terraform init` (uses local state) and `terraform apply` to create
       the bucket and the lock table.
    2. Uncomment the `backend "s3" {}` block, then run
       `terraform init -migrate-state` to move the state file into S3.
*/

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "portfolio-healthcheck-tfstate"
    key            = "healthcheck-lambda/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "portfolio-healthcheck-tfstate-lock"
    encrypt        = true
  }
}

# ---------------------------------------------------------------------------
# S3 bucket storing the terraform.tfstate file
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project_name}-tfstate"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table used for Terraform state locking
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
