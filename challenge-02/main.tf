# Route 53 - Hosted Zone
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# DNS bucket
resource "aws_route53_record" "s3_alias" {
  zone_id = aws_route53_zone.main.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_s3_bucket.static_website.website_endpoint
    zone_id                = aws_s3_bucket.static_website.hosted_zone_id
    evaluate_target_health = false
  }
}

# SSL/TLS
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  tags = {
    Name = "example-cert"
  }
}

# DNS
resource "aws_route53_record" "cert_validation" {
  count = length(aws_acm_certificate.cert.domain_validation_options)

  zone_id = aws_route53_zone.main.id
  name    = aws_acm_certificate.cert.domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options[count.index].resource_record_type
  ttl     = 60
  records = [aws_acm_certificate.cert.domain_validation_options[count.index].resource_record_value]
}

# Certificate Validation
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn = aws_acm_certificate.cert.arn

  validation_record_fqdns = aws_route53_record.cert_validation[*].fqdn
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "static_website" {
  origin {
    domain_name = aws_s3_bucket.static_website.website_endpoint
    origin_id   = "s3-static-website-origin"

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Custom SSL Certificate  
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method  = "sni-only"
  }

  default_cache_behavior {
    target_origin_id       = "s3-static-website-origin"
    allowed_methods        = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "static-website-distribution"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "static_website" {
  bucket = "${var.domain_name}-bucket"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

resource "aws_s3_bucket_object" "index" {
  bucket       = aws_s3_bucket.static_website.bucket
  key          = aws_s3_bucket_object.index.key
  source       = "files/index.html"
  acl          = "public-read"
  content_type = "text/html"
}


resource "aws_s3_bucket_policy" "static_website_policy" {
  bucket = aws_s3_bucket.static_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_website.arn}/*"
      }
    ]
  })
}