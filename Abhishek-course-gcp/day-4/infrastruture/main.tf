#devops engineer new -> needs access to create vm's 

resource "google_project_iam_custom_role" "devops_engineer" {
  role_id     = "devops_engineer_day_4"
  title       = "DevOps Engineer"
  description = "Role for DevOps Engineers"
  permissions = [
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setMetadata",
    "compute.projects.get",
  ]
}


# VM -> create
#list family image names: gcloud compute images list --project ubuntu-os-cloud --filter="family ~ 'ubuntu'" --format="value(family)" 
data "google_compute_image" "latest_ubuntu" {
  family  = "ubuntu-minimal-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

resource "google_compute_disk" "persistent_disk" {
  name = "devops-persistent-disk"
  type = "pd-standard"
  zone = var.gcp_zone
  size = 10
}

#https://cloud.google.com/compute/docs/regions-zones
resource "google_compute_instance" "devops_vm_instance" {
  name                      = "devops-vm-instance"
  machine_type              = "e2-small"
  zone                      = var.gcp_zone
  tags                      = ["http-server"] #applied from target tags
  allow_stopping_for_update = true
  deletion_protection       = false

  labels = {
    os = "ubuntu"
  }
  boot_disk {
    initialize_params {
      image = data.google_compute_image.latest_ubuntu.self_link
      size  = 10 #boot disk
    }
  }

  network_interface {
    network = "default"
    access_config {
      //  IPs via which this instance can be accessed via the Internet --> EVERYONE in this case
    }
  }

  attached_disk {
    source = google_compute_disk.persistent_disk.id #EXTRA 10 GB Added as per Video Instructions
  }
  #starup Script to execute automatically
  metadata_startup_script = file("startup.sh")
}



resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

#gcloud compute instances get-serial-port-output "devops-vm-instance" --zone "asia-south1-c" --project "gcp-zero-to-hero-123456" --- to verfiy startup.sh run or to debug it

#SSH login 
#gcloud compute ssh --zone "asia-south1-c" "devops-vm-instance" --project "gcp-zero-to-hero-WITH_ID"
#eg:
#gcloud compute ssh --zone "asia-south1-c" "devops-vm-instance" --project "gcp-zero-to-hero-123456"
