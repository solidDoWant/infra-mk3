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
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }

    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
