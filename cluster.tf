resource "aws_ecs_cluster" "app" {
  name = "${var.app_name}-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.app.arn
  }

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.app.id
      logging    = "DEFAULT"
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "app" {
  cluster_name       = aws_ecs_cluster.app.name
  capacity_providers = ["FARGATE"]
}

resource "aws_service_discovery_http_namespace" "app" {
  name        = var.app_name
  description = "${var.app_name} ECS services"
}

resource "aws_ecr_repository" "api" {
  name         = var.api_tags.Name
  force_delete = true # change to true before tearing down

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.api_tags
}

resource "aws_ecr_repository" "web" {
  name         = var.web_tags.Name
  force_delete = true # change to true before tearing down

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.web_tags
}

resource "aws_ecr_repository_policy" "web" {
  policy     = data.aws_iam_policy_document.repos.json
  repository = aws_ecr_repository.web.name
}

resource "aws_ecr_repository_policy" "api" {
  policy     = data.aws_iam_policy_document.repos.json
  repository = aws_ecr_repository.api.name
}

data "aws_iam_policy_document" "repos" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
    ]
  }
}

resource "aws_ecr_registry_scanning_configuration" "app" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*${var.app_name}*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.web_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  auto_accept         = true
}

