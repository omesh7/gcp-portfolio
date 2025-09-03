resource "google_compute_instance" "mario-vm" {
  name         = "mario-vm"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  allow_stopping_for_update = true
  deletion_protection       = false
  tags                      = ["mario-vm", "http-8080"]

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true #google def:  being replaced or displaced by something of higher priority or necessity
    automatic_restart  = false

  }


  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts" #used ubuntu instance
    }
  }


  network_interface {
    network = "default"
    access_config {
      //  IPs via which this instance can be accessed via the Internet --> EVERYONE in this case
    }
  }

  metadata_startup_script = file("startup-script.sh")


  #command to create own -> ssh-keygen -t rsa -b 4096 -f ssh-key -N ""
  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
  }

}

#task 2
resource "google_compute_firewall" "allow_8080" {
  name    = "allow-8080"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-8080"]
}



output "instance_ip" {
  value = google_compute_instance.mario-vm.network_interface[0].access_config[0].nat_ip
}
#ssh -i ssh-key gcp-user@34.47.164.192

#after provisioning it took some sweet time to take effect -> install initial scripts -> wait for it
#to see the output or debug it goto(inside the vm) => journalctl -u google-startup-scripts.service 


#---------------------------------------------------------------------