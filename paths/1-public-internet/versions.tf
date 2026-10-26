terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "continuum-private-pentest-demo"
      Path      = "1-public-internet"
      ManagedBy = "terraform"
      Purpose   = "security-agent-pentest-target"
      Warning   = "intentionally-vulnerable-do-not-expose"
    }
  }
}
