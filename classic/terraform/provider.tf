terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      #version = ">= v2.25.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}
