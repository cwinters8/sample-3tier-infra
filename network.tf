locals {
  api_cidr_blocks    = [for subnet in aws_subnet.api : subnet.cidr_block]
  web_cidr_blocks    = [for subnet in aws_subnet.web : subnet.cidr_block]
  public_cidr_blocks = [for subnet in aws_subnet.public : subnet.cidr_block]
  db_cidr_blocks     = [for subnet in aws_subnet.db : subnet.cidr_block]
  api_subnet_ids     = [for subnet in aws_subnet.api : subnet.id]
  web_subnet_ids     = [for subnet in aws_subnet.web : subnet.id]
  public_subnet_ids  = [for subnet in aws_subnet.public : subnet.id]
  task_subnet_ids = flatten([
    local.api_subnet_ids,
    local.web_subnet_ids
  ])
  task_sg_ids = [
    aws_security_group.api.id,
    aws_security_group.web.id
  ]
}

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.app.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
}

resource "aws_route_table_association" "public" {
  # for_each = toset([for subnet in aws_subnet.public : subnet.id])
  for_each = { for subnet in aws_subnet.public : subnet.availability_zone => subnet.id }

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.gw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_nat_gateway" "gw" {
  subnet_id         = aws_subnet.public["${data.aws_region.current.name}a"].id
  allocation_id     = aws_eip.nat_gw.allocation_id
  connectivity_type = "public"

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_eip" "nat_gw" {
  domain = "vpc"
}

resource "aws_route" "nat_gw" {
  route_table_id         = aws_vpc.app.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.gw.id
}

resource "aws_subnet" "web" {
  for_each = { for subnet in var.web_subnets : subnet.az => subnet }

  vpc_id            = aws_vpc.app.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = var.web_tags
}

resource "aws_subnet" "api" {
  for_each = { for subnet in var.api_subnets : subnet.az => subnet }

  vpc_id            = aws_vpc.app.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = var.api_tags
}

resource "aws_subnet" "db" {
  for_each = { for subnet in var.db_subnets : subnet.az => subnet }

  vpc_id            = aws_vpc.app.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = var.db_tags
}

resource "aws_subnet" "public" {
  for_each = { for subnet in var.public_subnets : subnet.az => subnet }

  vpc_id            = aws_vpc.app.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = var.public_tags
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.app.id

  ingress = [{
    description     = "public ingress"
    from_port       = var.web_port
    to_port         = var.web_port
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
    self            = true

    cidr_blocks      = local.public_cidr_blocks
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
  }]

  egress = [
    {
      description = "api egress"
      from_port   = var.api_port
      to_port     = var.api_port
      protocol    = "tcp"
      self        = true

      cidr_blocks      = local.api_cidr_blocks
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    },
    {
      description = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      self        = false

      cidr_blocks      = ["0.0.0.0/0"]
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    }
  ]

  tags = var.web_tags
}

resource "aws_security_group" "api" {
  vpc_id = aws_vpc.app.id

  ingress = [{
    description     = "web and public ingress"
    from_port       = var.api_port
    to_port         = var.api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.public.id]
    self            = true

    cidr_blocks = flatten([
      local.public_cidr_blocks,
      local.web_cidr_blocks
    ])
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
  }]

  egress = [
    {
      description = "db egress"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      self        = true

      cidr_blocks      = local.db_cidr_blocks
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    },
    {
      description = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      self        = false

      cidr_blocks      = ["0.0.0.0/0"]
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    }
  ]

  tags = var.api_tags
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.app.id

  ingress = [
    {
      description     = "API ingress"
      from_port       = var.db_port
      to_port         = var.db_port
      protocol        = "tcp"
      security_groups = [aws_security_group.api.id]
      self            = true

      cidr_blocks      = local.api_cidr_blocks
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    }
  ]

  egress = [
    {
      description = "internal egress"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      self        = true

      cidr_blocks      = []
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    },
    {
      description = "egress for AWS APIs used in Lambda function"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      self        = false

      cidr_blocks      = ["0.0.0.0/0"]
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    }
  ]

  tags = var.db_tags
}

resource "aws_security_group" "public" {
  vpc_id = aws_vpc.app.id

  ingress = [{
    description = "HTTPS ingress"
    from_port   = var.public_port
    to_port     = var.public_port
    protocol    = "tcp"
    self        = true

    cidr_blocks      = ["0.0.0.0/0"]
    security_groups  = []
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
  }]

  egress = [
    {
      description = "web egress"
      from_port   = var.web_port
      to_port     = var.web_port
      protocol    = "tcp"
      self        = true

      cidr_blocks      = local.web_cidr_blocks
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    },
    {
      description = "api egress"
      from_port   = var.api_port
      to_port     = var.api_port
      protocol    = "tcp"
      self        = true

      cidr_blocks      = local.api_cidr_blocks
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    },
    {
      description = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      self        = false

      cidr_blocks      = ["0.0.0.0/0"]
      security_groups  = []
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
    }
  ]

  tags = var.public_tags
}

resource "aws_security_group" "endpoints" {
  vpc_id = aws_vpc.app.id

  ingress = [{
    description = "VPC ingress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true

    cidr_blocks      = [aws_vpc.app.cidr_block]
    security_groups  = []
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
  }]

  egress = [{
    description = "VPC egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true

    cidr_blocks      = [aws_vpc.app.cidr_block]
    security_groups  = []
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
  }]
}
