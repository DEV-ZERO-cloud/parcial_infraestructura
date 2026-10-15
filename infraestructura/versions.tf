terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Estado local por simplicidad para el taller.
  # Mejora futura documentada: backend "s3" con bloqueo DynamoDB/S3 lockfile.
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