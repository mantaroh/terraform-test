variable "resource_prefix" {
  default = "terraform-test"
}
variable "use_cloudfront_function" {
  default = false
}
variable aws {}

terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.20.0"
    }
  }
}

provider "aws" {
  region                   = "${var.aws.region}"
  shared_credentials_files = [ "${var.aws.credential_file}" ]
  profile                  = "${var.aws.profile}"
}

data "aws_canonical_user_id" "current" {}

################################################################################
# S3 for testing
################################################################################
resource "aws_s3_bucket" "static_website" {
  bucket = "${var.resource_prefix}-static-website"
}

resource "aws_s3_bucket_policy" "static_website" {
  bucket = aws_s3_bucket.static_website.id
  policy = data.aws_iam_policy_document.static_website.json
}

data "aws_iam_policy_document" "static_website" {
  statement {
    sid    = "Allow CloudFront"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.static_website.iam_arn,
      ]
    }
    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.static_website.arn}/*"
    ]
  }
}

################################################################################
# CloudFront
################################################################################
/* Function */
resource "aws_cloudfront_function" "static_website_function" {
  comment = "address uri routing of cf."
  name    = "${var.resource_prefix}-static-website-function"
  runtime = "cloudfront-js-2.0"
  code    = file("assets/cloudfront/cf_routing.js")
  publish = true
}

resource "aws_cloudfront_distribution" "static_website" {
  origin {
    domain_name = aws_s3_bucket.static_website.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.static_website.id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_website.cloudfront_access_identity_path
    }
  }

  enabled = true

  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.static_website.id

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 60
    default_ttl            = 60
    max_ttl                = 60
    compress               = true

    # レスポンスのContent-Typeを書き換えるためのCloudFront Function
    dynamic function_association {
      for_each = var.use_cloudfront_function ? { sample: "sample" } : {}
      content {
        event_type   = "viewer-response"
        function_arn = aws_cloudfront_function.static_website_function.arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_cloudfront_origin_access_identity" "static_website" {

}

output "website_url" {
  value = "https://${aws_cloudfront_distribution.static_website.domain_name}/"
}
