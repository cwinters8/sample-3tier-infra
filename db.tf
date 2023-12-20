locals {
  db_subnet_ids             = [for subnet in aws_subnet.db : subnet.id]
  app_db_user_func_binary   = "bootstrap"
  app_db_user_func_dir      = "${path.module}/app_db_user_func"
  master_db_user_secret_arn = aws_rds_cluster.db.master_user_secret[0].secret_arn
  app_db_triggers = {
    index = var.app_db_pw_index
  }
}

resource "aws_db_subnet_group" "db" {
  name       = var.db_tags.Name
  subnet_ids = local.db_subnet_ids

  tags = var.db_tags
}

resource "aws_rds_cluster" "db" {
  cluster_identifier              = var.db_tags.Name
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = "15.2"
  db_subnet_group_name            = aws_db_subnet_group.db.name
  database_name                   = var.db_name
  master_username                 = "dbadmin"
  manage_master_user_password     = true
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.app.arn
  port                            = var.db_port
  backup_retention_period         = 30
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  vpc_security_group_ids          = [aws_security_group.db.id]

  # final_snapshot_identifier reflects the date the cluster was created, not the date it was deleted
  final_snapshot_identifier = "${var.db_tags.Name}-${formatdate("YYYYMMDD'T'hhmmssZZZ", timestamp())}"

  # scale these values appropriately for production workloads
  serverlessv2_scaling_configuration {
    max_capacity = 4
    min_capacity = 0.5
  }

  tags = var.db_tags

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_rds_cluster_instance" "db" {
  cluster_identifier                    = aws_rds_cluster.db.id
  engine                                = aws_rds_cluster.db.engine
  engine_version                        = aws_rds_cluster.db.engine_version
  instance_class                        = "db.serverless"
  db_subnet_group_name                  = aws_rds_cluster.db.db_subnet_group_name
  monitoring_interval                   = 15
  monitoring_role_arn                   = aws_iam_role.db_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.app.arn
  performance_insights_retention_period = 31
  copy_tags_to_snapshot                 = true

  tags = var.db_tags

  depends_on = [aws_iam_role_policy_attachment.db_monitoring]
}

resource "aws_lambda_invocation" "app_db_user_func" {
  function_name = aws_lambda_function.app_db_user_func.function_name
  input = jsonencode({
    admin_secret_arn = local.master_db_user_secret_arn
    db_host          = aws_rds_cluster.db.endpoint
    db_name          = aws_rds_cluster.db.database_name
    port             = aws_rds_cluster.db.port
    username         = "app"
    pw_secret_arn    = aws_secretsmanager_secret.app_db_pw.arn
  })

  triggers = local.app_db_triggers
}

output "dbname" {
  value = aws_rds_cluster.db.database_name
}

data "archive_file" "app_db_user_func" {
  type             = "zip"
  source_file      = "${local.app_db_user_func_dir}/${local.app_db_user_func_binary}"
  output_path      = "${local.app_db_user_func_dir}/bin/app_db_user_func.zip"
  output_file_mode = "0755"
}

resource "aws_lambda_function" "app_db_user_func" {
  function_name    = "${var.app_name}-db-user"
  description      = "creates the app database user"
  filename         = data.archive_file.app_db_user_func.output_path
  source_code_hash = data.archive_file.app_db_user_func.output_base64sha256
  role             = aws_iam_role.app_db_user_func.arn
  handler          = local.app_db_user_func_binary
  architectures    = ["arm64"]
  memory_size      = 256
  runtime          = "provided.al2023"
  timeout          = 30
  environment {
    variables = {
      AWS_ENABLE_ENDPOINT_DISCOVERY    = true
      AWS_ENDPOINT_URL_SECRETS_MANAGER = "secretsmanager.us-east-2.amazonaws.com"
    }
  }

  vpc_config {
    subnet_ids         = local.db_subnet_ids
    security_group_ids = [aws_security_group.db.id]
  }

  tags = var.db_tags

  depends_on = [
    aws_iam_role_policy_attachment.app_db_user_func_master_secret,
    aws_iam_role_policy_attachment.app_db_user_func_secret,
    aws_iam_role_policy_attachment.app_db_user_func_vpc_access,
    aws_vpc_endpoint.sm
  ]
}

resource "aws_vpc_endpoint" "sm" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.web_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  auto_accept         = true
}

resource "aws_iam_role" "app_db_user_func" {
  name               = "${var.app_name}-db-user-func"
  assume_role_policy = data.aws_iam_policy_document.func_assume_role_policy.json

  tags = var.db_tags
}

data "aws_iam_policy_document" "func_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "app_db_user_func_secret" {
  role       = aws_iam_role.app_db_user_func.name
  policy_arn = aws_iam_policy.app_db_pw_secret.arn
}

resource "aws_iam_role_policy_attachment" "app_db_user_func_master_secret" {
  role       = aws_iam_role.app_db_user_func.name
  policy_arn = aws_iam_policy.master_db_pw_secret.arn
}

resource "aws_iam_role_policy_attachment" "app_db_user_func_vpc_access" {
  role       = aws_iam_role.app_db_user_func.name
  policy_arn = data.aws_iam_policy.func_vpc_access.arn
}

data "aws_iam_policy" "func_vpc_access" {
  name = "AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "app_db_pw_secret" {
  name        = "${var.app_name}-db-user-secret"
  description = "Allows retrieval of the app DB user password from Secrets Manager"
  policy      = data.aws_iam_policy_document.app_db_pw_secret.json

  tags = var.db_tags
}

data "aws_iam_policy_document" "app_db_pw_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.app_db_pw.arn]
  }
}

resource "aws_iam_policy" "master_db_pw_secret" {
  name        = "${var.app_name}-db-master-pw-secret"
  description = "Allows retrieval of the DB master password from Secrets Manager"
  policy      = data.aws_iam_policy_document.master_db_pw_secret.json

  tags = var.db_tags
}

data "aws_iam_policy_document" "master_db_pw_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.master_db_user_secret_arn]
  }
}

resource "aws_iam_role" "db_monitoring" {
  name               = var.db_tags.Name
  assume_role_policy = data.aws_iam_policy_document.db_monitoring_assume_role_policy.json

  tags = var.db_tags
}

resource "aws_iam_role_policy_attachment" "db_monitoring" {
  role       = aws_iam_role.db_monitoring.name
  policy_arn = data.aws_iam_policy.rds_enhanced_monitoring.arn
}

data "aws_iam_policy_document" "db_monitoring_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "rds_enhanced_monitoring" {
  name = "AmazonRDSEnhancedMonitoringRole"
}

resource "aws_secretsmanager_secret" "app_db_pw" {
  name        = "${var.app_name}-db-pw-${var.app_db_pw_index}"
  description = "app db password for ${var.app_name}"

  tags = var.db_tags
}

resource "aws_secretsmanager_secret_version" "app_db_pw" {
  secret_id     = aws_secretsmanager_secret.app_db_pw.id
  secret_string = random_password.app_db_pw.result
}

resource "random_password" "app_db_pw" {
  length           = 20
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!$-+<>:"

  keepers = local.app_db_triggers
}

output "rds_cluster_arn" {
  value = aws_rds_cluster.db.arn
}

output "db_endpoint" {
  value = aws_rds_cluster.db.endpoint
}

output "master_db_user_secret_arn" {
  value = local.master_db_user_secret_arn
}

output "app_db_pw_secret_arn" {
  value = aws_secretsmanager_secret.app_db_pw.arn
}
