terraform {
  required_version = ">= 1.3"


  backend "s3" {
    bucket       = "rich-terraform-state-2026"
    key          = "eks/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
    
  }
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}


provider "aws" {
    region = "eu-north-1"
  
}