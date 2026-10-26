###############################################################################
# PATH 3 — VENDORED PYTHON WHEELS (strict zero-internet pip install)
#
# The app EC2 cannot reach PyPI (no NAT/IGW, no AWS-native PyPI endpoint). We
# vendor the Flask + pymysql wheel set into a private S3 bucket and have
# user-data install them with `pip install --no-index --find-links`. The GET
# traverses the S3 Gateway endpoint (endpoints.tf), so it stays inside the VPC.
#
# ONE-TIME WORKFLOW (on your internet-connected laptop — the VPC stays private):
#   1. ./vendor-wheels.sh      # downloads py3.9 / manylinux x86_64 wheels into ./wheels
#   2. terraform apply         # uploads ./wheels/* to this bucket, boots the instance
###############################################################################

locals {
  wheels_dir  = "${path.module}/wheels"
  wheel_files = fileset(local.wheels_dir, "*")
}

resource "aws_s3_bucket" "wheels" {
  bucket_prefix = "${var.name_prefix}-wheels-"
  force_destroy = true # demo bucket — allow terraform destroy to empty it
  tags          = { Name = "${var.name_prefix}-wheels" }
}

resource "aws_s3_bucket_public_access_block" "wheels" {
  bucket                  = aws_s3_bucket.wheels.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wheels" {
  bucket = aws_s3_bucket.wheels.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "wheel" {
  for_each = local.wheel_files

  bucket = aws_s3_bucket.wheels.id
  key    = "wheels/${each.value}"
  source = "${local.wheels_dir}/${each.value}"
  etag   = filemd5("${local.wheels_dir}/${each.value}")
}

# Fail the apply early with a clear message if the wheels were never vendored —
# otherwise the instance would boot and fail the offline pip install.
resource "terraform_data" "wheels_present_check" {
  input = length(local.wheel_files)

  lifecycle {
    precondition {
      condition     = length(local.wheel_files) > 0
      error_message = "This path needs vendored wheels. Run ./vendor-wheels.sh (needs internet on your machine) to populate paths/3-true-private/wheels/ before applying."
    }
  }
}
