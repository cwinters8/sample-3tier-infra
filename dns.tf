data "aws_route53_zone" "domain" {
  name = var.domain
}

resource "aws_acm_certificate" "domain" {
  domain_name               = var.domain
  subject_alternative_names = ["${var.api_service_name}.${var.domain}"]
  validation_method         = "DNS"

  tags = var.public_tags
}

resource "aws_route53_record" "validate_cert" {
  for_each = {
    for dvo in aws_acm_certificate.domain.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name            = each.value.name
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain.zone_id
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "domain" {
  certificate_arn         = aws_acm_certificate.domain.arn
  validation_record_fqdns = [for record in aws_route53_record.validate_cert : record.fqdn]
}
