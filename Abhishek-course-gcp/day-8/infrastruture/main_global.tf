# =============================================================================
# RANDOM ID GENERATION
# =============================================================================
resource "random_id" "suffix" {
  byte_length = 3
}

# =============================================================================
# NETWORKING - VPC AND SUBNETS
# =============================================================================

resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_name}-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  description             = "Main VPC network for Flask application"
}

resource "google_compute_subnetwork" "app_subnet" {
  name          = "${var.project_name}-app-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  description   = "Subnet for application instances"

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_subnetwork" "nat_subnet" {
  name          = "${var.project_name}-nat-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  description   = "Subnet for NAT gateway operations"

  depends_on = [google_compute_network.vpc_network]
}

# =============================================================================
# NAT GATEWAY FOR PRIVATE INSTANCE INTERNET ACCESS
# =============================================================================

resource "google_compute_router" "nat_router" {
  name        = "${var.project_name}-nat-router-${random_id.suffix.hex}"
  region      = var.gcp_region
  network     = google_compute_network.vpc_network.id
  description = "Router for Cloud NAT gateway"

  depends_on = [google_compute_subnetwork.nat_subnet]
}

resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.project_name}-nat-gateway-${random_id.suffix.hex}"
  router                             = google_compute_router.nat_router.name
  region                             = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  auto_network_tier                  = "PREMIUM"

  depends_on = [google_compute_router.nat_router]
}

# =============================================================================
# FIREWALL RULES
# =============================================================================

resource "google_compute_firewall" "allow_health_check" {
  name        = "${var.project_name}-allow-health-check-${random_id.suffix.hex}"
  network     = google_compute_network.vpc_network.name
  description = "Allow Google Cloud health check traffic on port 8080"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["http-server"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.project_name}-allow-ssh-${random_id.suffix.hex}"
  network     = google_compute_network.vpc_network.name
  description = "Allow SSH access to instances"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-server"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  depends_on = [google_compute_network.vpc_network]
}

# =============================================================================
# COMPUTE INSTANCE TEMPLATE
# =============================================================================

resource "google_compute_instance_template" "app_instance_template" {
  name         = "${var.project_name}-template-${random_id.suffix.hex}"
  machine_type = "e2-micro"
  description  = "Instance template for Flask application servers"

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.app_subnet.id
    # No access_config = private instances
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

  tags = ["http-server", "ssh-server"]

  depends_on = [
    google_compute_subnetwork.app_subnet,
    google_compute_router_nat.nat_gateway
  ]
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================

resource "google_compute_health_check" "app_health_check" {
  name                = "${var.project_name}-health-check-${random_id.suffix.hex}"
  description         = "Health check for Flask application"
  check_interval_sec  = 5
  timeout_sec         = 3
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    request_path = "/health"
    port         = "8080"
  }
}

# =============================================================================
# MANAGED INSTANCE GROUP AND AUTO-SCALING
# =============================================================================

resource "google_compute_instance_group_manager" "app_mig" {
  name               = "${var.project_name}-mig-${random_id.suffix.hex}"
  description        = "Managed Instance Group for Flask application servers"
  base_instance_name = "${var.project_name}-instance"
  zone               = "${var.gcp_region}-c"
  target_size        = 2

  auto_healing_policies {
    health_check      = google_compute_health_check.app_health_check.id
    initial_delay_sec = 180
  }

  named_port {
    name = "http"
    port = 8080
  }

  version {
    instance_template = google_compute_instance_template.app_instance_template.id
  }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
  }

  depends_on = [
    google_compute_instance_template.app_instance_template,
    google_compute_health_check.app_health_check
  ]
}

resource "google_compute_autoscaler" "app_autoscaler" {
  name        = "${var.project_name}-autoscaler-${random_id.suffix.hex}"
  zone        = "${var.gcp_region}-c"
  target      = google_compute_instance_group_manager.app_mig.id
  description = "Auto-scaler for Flask application instances"

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }

  depends_on = [google_compute_instance_group_manager.app_mig]
}

# =============================================================================
# GLOBAL LOAD BALANCER COMPONENTS
# =============================================================================

# Global static IP address
resource "google_compute_global_address" "lb_ip" {
  name         = "${var.project_name}-lb-ip-${random_id.suffix.hex}"
  description  = "Global static IP for load balancer"
  address_type = "EXTERNAL"
}

# Backend service - Global
resource "google_compute_backend_service" "app_backend" {
  name                  = "${var.project_name}-backend-${random_id.suffix.hex}"
  description           = "Backend service for Flask application"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.app_health_check.id]

  backend {
    group           = google_compute_instance_group_manager.app_mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  depends_on = [
    google_compute_instance_group_manager.app_mig,
    google_compute_health_check.app_health_check
  ]
}

# URL map - Global
resource "google_compute_url_map" "app_url_map" {
  name            = "${var.project_name}-url-map-${random_id.suffix.hex}"
  description     = "URL map for Flask application"
  default_service = google_compute_backend_service.app_backend.id

  depends_on = [google_compute_backend_service.app_backend]
}

# HTTP target proxy - Global
resource "google_compute_target_http_proxy" "app_proxy" {
  name        = "${var.project_name}-http-proxy-${random_id.suffix.hex}"
  description = "HTTP target proxy for Flask application"
  url_map     = google_compute_url_map.app_url_map.id

  depends_on = [google_compute_url_map.app_url_map]
}

# =============================================================================
# SSL CERTIFICATE AND HTTPS CONFIGURATION
# =============================================================================

# Google-managed SSL certificate - Global
resource "google_compute_managed_ssl_certificate" "app_ssl_cert" {
  name        = "${var.project_name}-ssl-cert-${random_id.suffix.hex}"
  description = "Google-managed SSL certificate for Flask application"

  managed {
    domains = [var.domain_name]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS target proxy - Global
resource "google_compute_target_https_proxy" "app_https_proxy" {
  name             = "${var.project_name}-https-proxy-${random_id.suffix.hex}"
  description      = "HTTPS target proxy for Flask application"
  url_map          = google_compute_url_map.app_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.app_ssl_cert.id]

  depends_on = [
    google_compute_url_map.app_url_map,
    google_compute_managed_ssl_certificate.app_ssl_cert
  ]
}

# =============================================================================
# GLOBAL FORWARDING RULES
# =============================================================================

# HTTP forwarding rule - Global
resource "google_compute_global_forwarding_rule" "app_forwarding_rule" {
  name                  = "${var.project_name}-http-forwarding-rule-${random_id.suffix.hex}"
  description           = "HTTP forwarding rule for Flask application"
  ip_address            = google_compute_global_address.lb_ip.address
  target                = google_compute_target_http_proxy.app_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [
    google_compute_global_address.lb_ip,
    google_compute_target_http_proxy.app_proxy
  ]
}

# HTTPS forwarding rule - Global
resource "google_compute_global_forwarding_rule" "app_https_forwarding_rule" {
  name                  = "${var.project_name}-https-forwarding-rule-${random_id.suffix.hex}"
  description           = "HTTPS forwarding rule for Flask application"
  ip_address            = google_compute_global_address.lb_ip.address
  target                = google_compute_target_https_proxy.app_https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [
    google_compute_global_address.lb_ip,
    google_compute_target_https_proxy.app_https_proxy
  ]
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "load_balancer_ip" {
  description = "Global external IP address of the load balancer"
  value       = google_compute_global_address.lb_ip.address
}

output "https_url" {
  description = "HTTPS URL for the Flask application"
  value       = "https://${var.domain_name}"
}

output "http_url" {
  description = "HTTP URL for the Flask application"
  value       = "http://${var.domain_name}"
}
# =============================================================================