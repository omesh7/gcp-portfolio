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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.8.4"
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


provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "zone" {
  zone_id = var.cloudflare_zone_id
}

