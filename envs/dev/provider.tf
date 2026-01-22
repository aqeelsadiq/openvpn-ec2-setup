terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.97.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment          = var.env
      Project              = var.identifier
      created_by_terraform = "true"
    }
  }
}
