terraform {
  backend "gcs" {
    bucket = "terraform-state-gcp-portfolio"
    prefix = "abisekh/day-11/state"
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

}

