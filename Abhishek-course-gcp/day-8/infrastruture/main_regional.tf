# =============================================================================
# RANDOM ID GENERATION
# =============================================================================
# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# NETWORKING - VPC AND SUBNETS
# =============================================================================

# Main VPC network with custom subnets
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_name}-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  description             = "Main VPC network for Flask application"
}

# Application subnet for private instances
resource "google_compute_subnetwork" "app_subnet" {
  name          = "${var.project_name}-app-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.1.0/24" # 256 IP addresses (10.0.1.0 - 10.0.1.255)
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  description   = "Subnet for application instances"

  depends_on = [google_compute_network.vpc_network]
}

# NAT subnet for Cloud NAT gateway
resource "google_compute_subnetwork" "nat_subnet" {
  name          = "${var.project_name}-nat-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.2.0/24" # 256 IP addresses for NAT operations
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  description   = "Subnet for NAT gateway operations"

  depends_on = [google_compute_network.vpc_network]
}

# Proxy-only subnet for Regional External HTTP Load Balancer
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "${var.project_name}-proxy-subnet-${random_id.suffix.hex}"
  ip_cidr_range = "10.0.3.0/24"            # 256 IP addresses for load balancer proxies
  purpose       = "REGIONAL_MANAGED_PROXY" # Required for Regional External LB
  role          = "ACTIVE"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  description   = "Proxy-only subnet for Regional External HTTP Load Balancer"

  depends_on = [google_compute_network.vpc_network]
}

# =============================================================================
# NAT GATEWAY FOR PRIVATE INSTANCE INTERNET ACCESS
# =============================================================================

# Cloud Router for NAT gateway
resource "google_compute_router" "nat_router" {
  name        = "${var.project_name}-nat-router-${random_id.suffix.hex}"
  region      = var.gcp_region
  network     = google_compute_network.vpc_network.id
  description = "Router for Cloud NAT gateway"

  depends_on = [google_compute_subnetwork.nat_subnet]
}

# Cloud NAT gateway for private instance internet access
resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.project_name}-nat-gateway-${random_id.suffix.hex}"
  router                             = google_compute_router.nat_router.name
  region                             = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"                     # Automatically allocate external IPs
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" # NAT for all subnets
  auto_network_tier                  = "PREMIUM"

  depends_on = [google_compute_router.nat_router]
}

# =============================================================================
# FIREWALL RULES
# =============================================================================

# Allow Google Cloud health check traffic to reach instances
resource "google_compute_firewall" "allow_health_check" {
  name        = "${var.project_name}-allow-health-check-${random_id.suffix.hex}"
  network     = google_compute_network.vpc_network.name
  description = "Allow Google Cloud health check traffic on port 8080"
  direction   = "INGRESS"
  priority    = 1000

  # Google Cloud health check IP ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["http-server"]

  allow {
    protocol = "tcp"
    ports    = ["8080"] # Flask application port
  }

  depends_on = [google_compute_network.vpc_network]
}

# Allow traffic from proxy-only subnet to application instances
resource "google_compute_firewall" "allow_proxy_only_subnet" {
  name        = "${var.project_name}-allow-proxy-only-${random_id.suffix.hex}"
  network     = google_compute_network.vpc_network.name
  description = "Allow traffic from proxy-only subnet to application instances"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["10.0.3.0/24"] # Proxy subnet CIDR
  target_tags   = ["http-server"]

  allow {
    protocol = "tcp"
    ports    = ["8080"] # Flask application port
  }

  depends_on = [google_compute_subnetwork.proxy_subnet]
}

# Allow SSH access to instances (for debugging and maintenance)
resource "google_compute_firewall" "allow_ssh" {
  name        = "${var.project_name}-allow-ssh-${random_id.suffix.hex}"
  network     = google_compute_network.vpc_network.name
  description = "Allow SSH access to instances"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["0.0.0.0/0"] # Allow from anywhere (consider restricting in production)
  target_tags   = ["ssh-server"]

  allow {
    protocol = "tcp"
    ports    = ["22"] # SSH port
  }

  depends_on = [google_compute_network.vpc_network]
}

# =============================================================================
# COMPUTE INSTANCE TEMPLATE
# =============================================================================

# Instance template for Flask application servers
resource "google_compute_region_instance_template" "app_instance_template" {
  name         = "${var.project_name}-template-${random_id.suffix.hex}"
  region       = var.gcp_region
  machine_type = "e2-micro" # Cost-effective machine type for demo
  description  = "Instance template for Flask application servers"

  # Boot disk configuration
  disk {
    source_image = "debian-cloud/debian-11" # Debian 11 base image
    auto_delete  = true
    boot         = true
  }

  # Network configuration - private instances only
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.app_subnet.id
    # No access_config block = no external IP (private instances)
  }

  # SSH key for access (optional - GCP can generate keys automatically)
  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
  }

  # Startup script to install and configure Flask application
  metadata_startup_script = file("startup.sh")

  # Use Spot instances for cost savings
  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  # Network tags for firewall rules
  tags = ["http-server", "ssh-server"]

  depends_on = [
    google_compute_subnetwork.app_subnet,
    google_compute_router_nat.nat_gateway # Ensure NAT is available for startup script
  ]
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================

# Health check for Managed Instance Group auto-healing
resource "google_compute_region_health_check" "mig_health_check" {
  name                = "${var.project_name}-mig-health-check-${random_id.suffix.hex}"
  region              = var.gcp_region
  description         = "Health check for MIG auto-healing"
  check_interval_sec  = 5 # Check every 5 seconds
  timeout_sec         = 3 # 3 second timeout
  healthy_threshold   = 2 # 2 consecutive successes = healthy
  unhealthy_threshold = 3 # 3 consecutive failures = unhealthy (15 seconds total)

  http_health_check {
    request_path = "/health" # Flask health endpoint
    port         = "8080"    # Flask application port
  }
}

# Health check for Load Balancer backend service
resource "google_compute_region_health_check" "lb_health_check" {
  name                = "${var.project_name}-lb-health-check-${random_id.suffix.hex}"
  region              = var.gcp_region
  description         = "Health check for load balancer backend service"
  check_interval_sec  = 5  # Check every 5 seconds
  timeout_sec         = 5  # 5 second timeout
  healthy_threshold   = 2  # 2 consecutive successes = healthy
  unhealthy_threshold = 10 # 10 consecutive failures = unhealthy (50 seconds total)

  http_health_check {
    request_path = "/health" # Flask health endpoint
    port         = "8080"    # Flask application port
  }
}

# =============================================================================
# MANAGED INSTANCE GROUP AND AUTO-SCALING
# =============================================================================

# Managed Instance Group for automatic instance management
resource "google_compute_region_instance_group_manager" "app_mig" {
  name                             = "${var.project_name}-mig-${random_id.suffix.hex}"
  description                      = "Managed Instance Group for Flask application servers"
  base_instance_name               = "${var.project_name}-instance"
  region                           = var.gcp_region
  target_size                      = 2                       # Initial number of instances
  distribution_policy_target_shape = "SINGLE_ZONE"           # Deploy in single zone for cost savings
  distribution_policy_zones        = ["${var.gcp_region}-c"] # Specific zone

  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_region_health_check.mig_health_check.id
    initial_delay_sec = 180 # Wait 3 minutes after instance creation before health checking
  }

  # Named port for load balancer backend service
  named_port {
    name = "http"
    port = 8080 # Flask application port
  }

  # Instance template version
  version {
    instance_template = google_compute_region_instance_template.app_instance_template.self_link
  }

  depends_on = [
    google_compute_region_instance_template.app_instance_template,
    google_compute_region_health_check.mig_health_check
  ]
}

# Auto-scaler for dynamic instance scaling based on CPU utilization
resource "google_compute_region_autoscaler" "app_autoscaler" {
  name        = "${var.project_name}-autoscaler-${random_id.suffix.hex}"
  region      = var.gcp_region
  target      = google_compute_region_instance_group_manager.app_mig.id
  description = "Auto-scaler for Flask application instances"

  autoscaling_policy {
    min_replicas    = 2  # Minimum 2 instances for high availability
    max_replicas    = 6  # Maximum 6 instances for cost control
    cooldown_period = 60 # Wait 60 seconds between scaling operations

    # Scale based on CPU utilization
    cpu_utilization {
      target = 0.6 # Scale up when average CPU > 60%
    }
  }

  depends_on = [google_compute_region_instance_group_manager.app_mig]
}

# =============================================================================
# LOAD BALANCER COMPONENTS
# =============================================================================

# Static external IP address for load balancer
resource "google_compute_address" "lb_ip" {
  name         = "${var.project_name}-lb-ip-${random_id.suffix.hex}"
  region       = var.gcp_region
  description  = "Static external IP for load balancer"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

# Backend service - defines how traffic is distributed to instances
resource "google_compute_region_backend_service" "app_backend" {
  name                  = "${var.project_name}-backend-${random_id.suffix.hex}"
  region                = var.gcp_region
  description           = "Backend service for Flask application"
  protocol              = "HTTP"
  port_name             = "http"             # Must match named_port in MIG
  load_balancing_scheme = "EXTERNAL_MANAGED" # Regional External HTTP Load Balancer
  timeout_sec           = 30                 # Backend timeout
  health_checks         = [google_compute_region_health_check.lb_health_check.id]

  # Backend configuration
  backend {
    group           = google_compute_region_instance_group_manager.app_mig.instance_group
    balancing_mode  = "UTILIZATION" # Distribute based on CPU utilization
    capacity_scaler = 1.0           # Use 100% of backend capacity
  }

  depends_on = [
    google_compute_region_instance_group_manager.app_mig,
    google_compute_region_health_check.lb_health_check
  ]
}

# URL map - defines routing rules (simple case: all traffic to one backend)
resource "google_compute_region_url_map" "app_url_map" {
  name            = "${var.project_name}-url-map-${random_id.suffix.hex}"
  region          = var.gcp_region
  description     = "URL map for Flask application"
  default_service = google_compute_region_backend_service.app_backend.id

  depends_on = [google_compute_region_backend_service.app_backend]
}

# HTTP target proxy - handles HTTP traffic
resource "google_compute_region_target_http_proxy" "app_proxy" {
  name        = "${var.project_name}-http-proxy-${random_id.suffix.hex}"
  region      = var.gcp_region
  description = "HTTP target proxy for Flask application"
  url_map     = google_compute_region_url_map.app_url_map.id

  depends_on = [google_compute_region_url_map.app_url_map]
}

# =============================================================================
# FORWARDING RULES (FRONTEND CONFIGURATION)
# =============================================================================

# HTTP forwarding rule - routes HTTP traffic (port 80) to HTTP proxy
resource "google_compute_forwarding_rule" "app_forwarding_rule" {
  name                  = "${var.project_name}-http-forwarding-rule-${random_id.suffix.hex}"
  region                = var.gcp_region
  description           = "HTTP forwarding rule for Flask application"
  ip_address            = google_compute_address.lb_ip.address
  target                = google_compute_region_target_http_proxy.app_proxy.id
  port_range            = "80" # HTTP port
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network               = google_compute_network.vpc_network.id
  network_tier          = "PREMIUM"

  depends_on = [
    google_compute_address.lb_ip,
    google_compute_region_target_http_proxy.app_proxy,
    google_compute_subnetwork.proxy_subnet
  ]
}

# =============================================================================
# OUTPUTS
# =============================================================================

# Load balancer external IP address - HTTP only
output "load_balancer_ip" {
  description = "External IP address of the load balancer (HTTP only)"
  value       = "http://${google_compute_address.lb_ip.address}"
}