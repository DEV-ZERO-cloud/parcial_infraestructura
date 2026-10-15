terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Estado remoto en S3 con bloqueo DynamoDB para permitir terraform apply desde CI.
  # El bucket y la tabla se crean una sola vez antes de migrar el estado local.
  backend "s3" {
    bucket         = "estrella-tfstate-704932818752"
    key            = "parcial/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "estrella-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      equipo   = var.team
      proyecto = var.project
    }
  }
}