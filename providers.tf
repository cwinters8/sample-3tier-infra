terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.29"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    region         = "us-east-2"
    bucket         = "3tier-app-infra"
    key            = "tf/terraform.tfstate"
    dynamodb_table = "3tier-app-infra"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      "Name"       = var.app_name
      "service"    = var.app_name
      "managed_by" = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
