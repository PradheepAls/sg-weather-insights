terraform {
  required_version = ">= 1.11.0" # ephemeral values + write-only secret arguments

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial config, one state per environment:
  #   terraform init -backend-config="bucket=<state-bucket>" -backend-config="key=sgw/dev.tfstate" \
  #                  -backend-config="region=ap-southeast-1" -backend-config="use_lockfile=true"
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "sg-weather-insights"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
