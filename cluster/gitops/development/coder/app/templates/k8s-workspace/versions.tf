terraform {
  required_version = "~> 1.13"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.13"
    }

    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }

    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }

    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
