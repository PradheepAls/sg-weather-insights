terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  # Partial config: terraform init -backend-config=../../backend.hcl -backend-config="key=foundation.tfstate"
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.project, ManagedBy = "terraform", Stack = "foundation", Repository = var.github_repository }
  }
}
