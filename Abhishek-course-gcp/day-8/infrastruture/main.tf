
#step -1
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false

}

resource "google_compute_subnetwork" "app_subnet" {
  name          = "${var.project_name}-app-subnet"
  ip_cidr_range = "10.0.1.0/24" #gives about 256 IPs range => 10.0.1.0 - 10.0.1.255 => 32-24 = 8 so, 2^8 = 256Ips
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id

}

resource "google_compute_subnetwork" "nat_subnet" {
  name          = "${var.project_name}-nat-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = google_compute_subnetwork.app_subnet.region
  network       = google_compute_network.vpc_network.id
}


#step -2 NAT Gateway Router
resource "google_compute_router" "nat_router" {
  name    = "${var.project_name}-nat-router"
  region  = google_compute_subnetwork.nat_subnet.region
  network = google_compute_network.vpc_network.id
}


resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.project_name}-nat-gateway"
  router                             = google_compute_router.nat_router.name
  region                             = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  auto_network_tier                  = "PREMIUM"
  depends_on                         = [google_compute_subnetwork.nat_subnet]
}

#step 3 firewalls
resource "google_compute_firewall" "allow_health_check" {
  name        = "${var.project_name}-allow-health-check"
  network     = google_compute_network.vpc_network.name
  description = "Allows Health check traffic"
  direction   = "INGRESS"

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  priority      = 1000
  target_tags   = ["http-server"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
  }

}

resource "google_compute_firewall" "allow_proxy_only_subnet" {
  name        = "${var.project_name}-allow-proxy-only"
  network     = google_compute_network.vpc_network.name
  description = "Allows proxy-only subnet traffic"
  direction   = "INGRESS"

  source_ranges = ["10.0.3.0/24"]
  priority      = 1000
  target_tags   = ["http-server"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
  }

}




resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.project_name}-allow-ssh"
  network     = google_compute_network.vpc_network.name
  description = "Allows SSH access"
  direction   = "INGRESS"

  source_ranges = ["0.0.0.0/0"]
  priority      = 1000
  target_tags   = ["ssh-server"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false
  }
}


#step 4 Instance Template
resource "google_compute_region_instance_template" "day_8_template" {
  name         = "${var.project_name}-template"
  region       = var.gcp_region
  machine_type = "e2-micro"

  disk {
    source_image = "debian-cloud/debian-11"
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.app_subnet.id
    # No access_config = no external IP (private instances)
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
  }

  metadata_startup_script = file("startup.sh")

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = false

  }
  tags = ["http-server", "ssh-server"]
}


#task 5: Managed Instance Group single zone

#automatically check if healthy or remove and recreate if not
resource "google_compute_health_check" "app_health_check" {
  name                = "${var.project_name}-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  log_config {
    enable = true
  }

  http_health_check {
    request_path = "/health"
    port         = "8080"
  }
}



resource "google_compute_region_instance_group_manager" "day-8-mig" {
  name                             = "${var.project_name}-mig"
  description                      = "Managed Instance Group for app servers single zone"
  base_instance_name               = "${var.project_name}-instance"
  region                           = var.gcp_region
  target_size                      = 2
  distribution_policy_target_shape = "SINGLE_ZONE"
  distribution_policy_zones        = ["${var.gcp_region}-c"]

  auto_healing_policies {
    health_check      = google_compute_health_check.app_health_check.id
    initial_delay_sec = 400
  }

  named_port {
    name = "http"
    port = 8080
  }

  version {
    instance_template = google_compute_region_instance_template.day_8_template.self_link
  }

  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false
  }
}

resource "google_compute_region_autoscaler" "web_autoscaler" {
  name   = "${var.project_name}-autoscaler"
  region = var.gcp_region
  target = google_compute_region_instance_group_manager.day-8-mig.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.6 #60 % usage
    }
  }
}

#step 6 load balancer

#proxy subnet
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "${var.project_name}-proxy-subnet"
  ip_cidr_range = "10.0.3.0/24"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_health_check" "web_health_check" {
  name                = "${var.project_name}-web-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10

  http_health_check {
    request_path = "/health"
    port         = "8080"
  }
}

resource "google_compute_address" "lb_ip" {
  name   = "${var.project_name}-lb-ip"
  region = var.gcp_region
}

resource "google_compute_region_backend_service" "web_backend" {
  name                  = "${var.project_name}-backend"
  region                = var.gcp_region
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.web_health_check.id]



  backend {
    group           = google_compute_region_instance_group_manager.day-8-mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}



resource "google_compute_region_url_map" "web_url_map" {
  name            = "${var.project_name}-url-map"
  region          = var.gcp_region
  default_service = google_compute_region_backend_service.web_backend.id
}


resource "google_compute_region_target_http_proxy" "web_proxy" {
  name    = "${var.project_name}-http-proxy"
  region  = var.gcp_region
  url_map = google_compute_region_url_map.web_url_map.id
}

resource "google_compute_forwarding_rule" "web_forwarding_rule" {
  name                  = "${var.project_name}-forwarding-rule"
  region                = var.gcp_region
  ip_address            = google_compute_address.lb_ip.address
  target                = google_compute_region_target_http_proxy.web_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network               = google_compute_network.vpc_network.id
  network_tier          = "STANDARD"
}

# Output the frontend IP
output "load_balancer_ip" {
  description = "Frontend IP address of the load balancer"
  value       = google_compute_address.lb_ip.address
}
