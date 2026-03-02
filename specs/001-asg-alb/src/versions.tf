terraform {
  required_version = ">= 1.9"

  cloud {
    organization = "hashi-demos-apj"
    workspaces {
      name    = "sandbox-consumer-asg-alb"
      project = "sandbox"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
