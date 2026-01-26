terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Local state for bootstrap - this is intentional
  # After bootstrap, the main terraform uses GCS backend
}

provider "google" {
  project = var.project_id
  region  = var.region
}
