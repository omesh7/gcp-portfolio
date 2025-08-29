terraform {
  backend "gcs" {
    bucket = "terraform-state-gcp-portfolio"
    prefix = "abisekh/day-8/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.49.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  default_labels = {
    environment = "dev"
    terraform   = "true"
    day         = "8"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

