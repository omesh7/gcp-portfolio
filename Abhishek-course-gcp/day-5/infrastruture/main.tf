#TASK 1
resource "google_storage_bucket" "my_bucket" {
  name          = "abisekh-day-5-gcp-portfolio-bucket"
  location      = "ASIA-SOUTH1"
  storage_class = "STANDARD"
  project       = var.gcp_project_id

  lifecycle_rule {
    condition {
      age = 2
    }
    action {
      type = "Delete"
    }
  }

}

resource "google_storage_bucket_object" "hello_object" {
  name   = "hello.txt"
  bucket = google_storage_bucket.my_bucket.name
  source = "hello.txt"
}

#TASK 2

resource "google_service_account" "task_2_service_account" {
  account_id   = var.gcp_project_id
  display_name = "gcs-demo-sa"
}

resource "google_project_iam_binding" "task_2_iam_policy" {
  project = var.gcp_project_id
  role    = "roles/storage.objectAdmin"
  members = ["serviceAccount:${google_service_account.task_2_service_account.email}"]
}


#TASK 3 create Vm with gcs-service account

resource "google_compute_instance" "gcs-vm" {
  name         = "gcs-vm"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  allow_stopping_for_update = true
  deletion_protection       = false
  tags                      = ["gcs-vm"]

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true #google def:  being replaced or displaced by something of higher priority or necessity
    automatic_restart  = false
  }


  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }


  network_interface {
    network = "default"
    access_config {
      //  IPs via which this instance can be accessed via the Internet --> EVERYONE in this case
    }
  }

  service_account {
    email  = google_service_account.task_2_service_account.email
    scopes = ["cloud-platform"]
  }
}

#task 4
#commands inside vm
#gcloud compute ssh --zone "asia-south1-c" "gcs-vm" --project "gcp-zero-to-hero-123456"

# gcloud storage ls gs://abisekh-day-5-gcp-portfolio-bucket
#THERE SHOULD BE A FILE NAMED hello.txt

#copy to current folder 
#gcloud storage cp gs://abisekh-day-5-gcp-portfolio-bucket/hello.txt .

#view it
#cat hello.txt


