
# [ original version ] 

# discarded cause google_compute_managed_ssl_certificate  =>  global only so HTTPS DOSENT WORK 
# so splitted and reformatted regional and global
#comment out one to deploy the other
#note: provisioning domain takes a longgg time like 24h so,

#tried to to use  Cloudflare Origin certificates for regional load balancers but some error happens so, for now using global 

#step -1 
# resource "google_compute_network" "vpc_network" {
#   name                    = "${var.project_name}-vpc"
#   auto_create_subnetworks = false

# }

# resource "google_compute_subnetwork" "app_subnet" {
#   name          = "${var.project_name}-app-subnet"
#   ip_cidr_range = "10.0.1.0/24" #gives about 256 IPs range => 10.0.1.0 - 10.0.1.255 => 32-24 = 8 so, 2^8 = 256Ips
#   region        = var.gcp_region
#   network       = google_compute_network.vpc_network.id

#   depends_on = [google_compute_network.vpc_network]
# }

# resource "google_compute_subnetwork" "nat_subnet" {
#   name          = "${var.project_name}-nat-subnet"
#   ip_cidr_range = "10.0.2.0/24"
#   region        = google_compute_subnetwork.app_subnet.region
#   network       = google_compute_network.vpc_network.id

#   depends_on = [google_compute_network.vpc_network]
# }


# #step -2 NAT Gateway Router
# resource "google_compute_router" "nat_router" {
#   name    = "${var.project_name}-nat-router"
#   region  = google_compute_subnetwork.nat_subnet.region
#   network = google_compute_network.vpc_network.id

#   depends_on = [google_compute_subnetwork.nat_subnet]
# }


# resource "google_compute_router_nat" "nat_gateway" {
#   name                               = "${var.project_name}-nat-gateway"
#   router                             = google_compute_router.nat_router.name
#   region                             = google_compute_router.nat_router.region
#   nat_ip_allocate_option             = "AUTO_ONLY"
#   source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
#   auto_network_tier                  = "PREMIUM"

#   depends_on = [google_compute_router.nat_router]
# }

# #step 3 firewalls
# resource "google_compute_firewall" "allow_health_check" {
#   name        = "${var.project_name}-allow-health-check"
#   network     = google_compute_network.vpc_network.name
#   description = "Allows Health check traffic"
#   direction   = "INGRESS"

#   source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
#   priority      = 1000
#   target_tags   = ["http-server"]

#   allow {
#     protocol = "tcp"
#     ports    = ["8080"]
#   }

#   lifecycle {
#     prevent_destroy       = false
#     create_before_destroy = false
#   }

#   depends_on = [google_compute_network.vpc_network]
# }

# resource "google_compute_firewall" "allow_proxy_only_subnet" {
#   name        = "${var.project_name}-allow-proxy-only"
#   network     = google_compute_network.vpc_network.name
#   description = "Allows proxy-only subnet traffic"
#   direction   = "INGRESS"

#   source_ranges = ["10.0.3.0/24"]
#   priority      = 1000
#   target_tags   = ["http-server"]

#   allow {
#     protocol = "tcp"
#     ports    = ["8080"]
#   }

#   lifecycle {
#     prevent_destroy       = false
#     create_before_destroy = false
#   }

#   depends_on = [google_compute_subnetwork.proxy_subnet]
# }


# resource "google_compute_firewall" "allow_ssh" {
#   name        = "${var.project_name}-allow-ssh"
#   network     = google_compute_network.vpc_network.name
#   description = "Allows SSH access"
#   direction   = "INGRESS"

#   source_ranges = ["0.0.0.0/0"]
#   priority      = 1000
#   target_tags   = ["ssh-server"]

#   allow {
#     protocol = "tcp"
#     ports    = ["22"]
#   }

#   lifecycle {
#     prevent_destroy       = false
#     create_before_destroy = false
#   }

#   depends_on = [google_compute_network.vpc_network]
# }


# #step 4 Instance Template
# resource "google_compute_region_instance_template" "app_instance_template" {
#   name         = "${var.project_name}-template"
#   region       = var.gcp_region
#   machine_type = "e2-micro"


#   disk {
#     source_image = "debian-cloud/debian-11"
#   }

#   network_interface {
#     network    = google_compute_network.vpc_network.id
#     subnetwork = google_compute_subnetwork.app_subnet.id
#     # No access_config = no external IP (private instances)
#   }

#   metadata = {
#     ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}" #extra created for local connect not needed gcp creates one for you 
#   }

#   metadata_startup_script = file("startup.sh")

#   scheduling {
#     provisioning_model = "SPOT"
#     preemptible        = true
#     automatic_restart  = false
#   }

#   lifecycle {
#     prevent_destroy       = false
#     create_before_destroy = false
#   }

#   tags = ["http-server", "ssh-server"]

#   depends_on = [
#     google_compute_subnetwork.app_subnet,
#     google_compute_router_nat.nat_gateway
#   ]
# }


# #task 5: Managed Instance Group single zone

# #automatically check if healthy or remove and recreate if not
# resource "google_compute_region_health_check" "mig_health_check" {
#   name                = "${var.project_name}-mig-health-check"
#   region              = var.gcp_region
#   check_interval_sec  = 5
#   timeout_sec         = 3
#   healthy_threshold   = 2
#   unhealthy_threshold = 3 # 15 seconds (3 × 5 sec intervals)

#   http_health_check {
#     request_path = "/health"
#     port         = "8080"
#   }
# }



# resource "google_compute_region_instance_group_manager" "day-8-mig" {
#   name                             = "${var.project_name}-mig"
#   description                      = "Managed Instance Group for app servers single zone"
#   base_instance_name               = "${var.project_name}-instance"
#   region                           = var.gcp_region
#   target_size                      = 2
#   distribution_policy_target_shape = "SINGLE_ZONE"
#   distribution_policy_zones        = ["${var.gcp_region}-c"]

#   auto_healing_policies {
#     health_check      = google_compute_region_health_check.mig_health_check.id
#     initial_delay_sec = 180 # 3 minutes for app startup
#   }

#   named_port {
#     name = "http"
#     port = 8080
#   }

#   version {
#     instance_template = google_compute_region_instance_template.app_instance_template.self_link
#   }

#   lifecycle {
#     create_before_destroy = false
#     prevent_destroy       = false
#   }

#   depends_on = [
#     google_compute_region_instance_template.app_instance_template,
#     google_compute_region_health_check.mig_health_check
#   ]
# }

# resource "google_compute_region_autoscaler" "app_autoscaler" {
#   name   = "${var.project_name}-autoscaler"
#   region = var.gcp_region
#   target = google_compute_region_instance_group_manager.day-8-mig.id

#   autoscaling_policy {
#     min_replicas    = 2
#     max_replicas    = 6
#     cooldown_period = 60

#     cpu_utilization {
#       target = 0.6 #60 % usage
#     }
#   }

#   depends_on = [google_compute_region_instance_group_manager.day-8-mig]
# }

# #step 6 load balancer

# #proxy subnet - managed via firewall : allow_proxy_only_subnet
# resource "google_compute_subnetwork" "proxy_subnet" {
#   name          = "${var.project_name}-proxy-subnet"
#   ip_cidr_range = "10.0.3.0/24"
#   purpose       = "REGIONAL_MANAGED_PROXY" #only regional managed proxy here
#   role          = "ACTIVE"
#   region        = var.gcp_region
#   network       = google_compute_network.vpc_network.id

#   depends_on = [google_compute_network.vpc_network]
# }

# resource "google_compute_region_health_check" "lb_health_check" {
#   name                = "${var.project_name}-lb-health-check"
#   region              = var.gcp_region
#   check_interval_sec  = 5
#   timeout_sec         = 5
#   healthy_threshold   = 2
#   unhealthy_threshold = 10

#   http_health_check {
#     request_path = "/health"
#     port         = "8080"
#   }
# }

# resource "google_compute_address" "lb_ip" {
#   name   = "${var.project_name}-lb-ip"
#   region = var.gcp_region
# }

# resource "google_compute_region_backend_service" "app_backend" {
#   name                  = "${var.project_name}-backend"
#   region                = var.gcp_region
#   protocol              = "HTTP"
#   port_name             = "http"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   timeout_sec           = 30
#   health_checks         = [google_compute_region_health_check.lb_health_check.id]

#   backend {
#     group           = google_compute_region_instance_group_manager.day-8-mig.instance_group
#     balancing_mode  = "UTILIZATION"
#     capacity_scaler = 1.0
#   }

#   depends_on = [
#     google_compute_region_instance_group_manager.day-8-mig,
#     google_compute_region_health_check.lb_health_check
#   ]
# }



# resource "google_compute_region_url_map" "app_url_map" {
#   name            = "${var.project_name}-url-map"
#   region          = var.gcp_region
#   default_service = google_compute_region_backend_service.app_backend.id

#   depends_on = [google_compute_region_backend_service.app_backend]
# }


# resource "google_compute_region_target_http_proxy" "app_proxy" {
#   name    = "${var.project_name}-http-proxy"
#   region  = var.gcp_region
#   url_map = google_compute_region_url_map.app_url_map.id

#   depends_on = [google_compute_region_url_map.app_url_map]
# }

# # Google-managed SSL certificate
# resource "google_compute_managed_ssl_certificate" "app_ssl_cert" {
#   name = "${var.project_name}-ssl-cert"

#   managed {
#     domains = [var.domain_name]
#   }
# }

# resource "google_compute_region_target_https_proxy" "app_https_proxy" {
#   name             = "${var.project_name}-https-proxy"
#   region           = var.gcp_region
#   url_map          = google_compute_region_url_map.app_url_map.id
#   ssl_certificates = [google_compute_managed_ssl_certificate.app_ssl_cert.id]

#   depends_on = [
#     google_compute_region_url_map.app_url_map,
#     google_compute_managed_ssl_certificate.app_ssl_cert
#   ]
# }

# resource "google_compute_forwarding_rule" "app_forwarding_rule" {
#   name                  = "${var.project_name}-forwarding-rule"
#   region                = var.gcp_region
#   ip_address            = google_compute_address.lb_ip.address
#   target                = google_compute_region_target_http_proxy.app_proxy.id
#   port_range            = "80"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   network               = google_compute_network.vpc_network.id
#   network_tier          = "PREMIUM"

#   depends_on = [
#     google_compute_address.lb_ip,
#     google_compute_region_target_http_proxy.app_proxy,
#     google_compute_subnetwork.proxy_subnet
#   ]
# }

# resource "google_compute_forwarding_rule" "app_https_forwarding_rule" {
#   name                  = "${var.project_name}-https-forwarding-rule"
#   region                = var.gcp_region
#   ip_address            = google_compute_address.lb_ip.address
#   target                = google_compute_region_target_https_proxy.app_https_proxy.id
#   port_range            = "443"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   network               = google_compute_network.vpc_network.id
#   network_tier          = "PREMIUM"

#   depends_on = [
#     google_compute_address.lb_ip,
#     google_compute_region_target_https_proxy.app_https_proxy,
#     google_compute_subnetwork.proxy_subnet
#   ]
# }

# # Outputs
# output "load_balancer_ip" {
#   description = "Load balancer IP address"
#   value       = google_compute_address.lb_ip.address
# }

# output "https_url" {
#   description = "HTTPS URL for the Flask app"
#   value       = "https://${var.domain_name}"

#   depends_on = [
#     google_compute_region_url_map.app_url_map,
#     google_compute_region_ssl_certificate.cloudflare_origin_cert
#   ]
# }

# resource "google_compute_forwarding_rule" "app_forwarding_rule" {
#   name                  = "${var.project_name}-forwarding-rule"
#   region                = var.gcp_region
#   ip_address            = google_compute_address.lb_ip.address
#   target                = google_compute_region_target_http_proxy.app_proxy.id
#   port_range            = "80"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   network               = google_compute_network.vpc_network.id
#   network_tier          = "PREMIUM"

#   depends_on = [
#     google_compute_address.lb_ip,
#     google_compute_region_target_http_proxy.app_proxy,
#     google_compute_subnetwork.proxy_subnet
#   ]
# }

# resource "google_compute_forwarding_rule" "app_https_forwarding_rule" {
#   name                  = "${var.project_name}-https-forwarding-rule"
#   region                = var.gcp_region
#   ip_address            = google_compute_address.lb_ip.address
#   target                = google_compute_region_target_https_proxy.app_https_proxy.id
#   port_range            = "443"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   network               = google_compute_network.vpc_network.id
#   network_tier          = "PREMIUM"

#   depends_on = [
#     google_compute_address.lb_ip,
#     google_compute_region_target_https_proxy.app_https_proxy,
#     google_compute_subnetwork.proxy_subnet
#   ]
# }

# #step-7 HTTPS with Cloudflare Domain
# # SSL Certificate using Cloudflare Origin Certificate
# resource "google_compute_region_ssl_certificate" "cloudflare_origin_cert" {
#   region      = var.gcp_region
#   name        = "${var.project_name}-cloudflare-origin-cert"
#   certificate = cloudflare_origin_ca_certificate.origin_cert.certificate
#   private_key = tls_private_key.origin_key.private_key_pem

#   depends_on = [cloudflare_origin_ca_certificate.origin_cert]
# }

# # Cloudflare DNS record
# resource "cloudflare_dns_record" "www_a_record" {
#   zone_id = var.cloudflare_zone_id
#   name    = var.subdomain_name
#   type    = "A"
#   content = google_compute_address.lb_ip.address
#   ttl     = 1
#   proxied = true

#   lifecycle {
#     prevent_destroy       = false
#     create_before_destroy = true
#   }
#   depends_on = [google_compute_address.lb_ip]
# }

# # Fix the HTTPS forwarding rule to include network and network_tier
# resource "google_compute_forwarding_rule" "app_forwarding_rule_https" {
#   name                  = "${var.project_name}-forwarding-rule-https"
#   region                = var.gcp_region
#   ip_address            = google_compute_address.lb_ip.address
#   target                = google_compute_region_target_https_proxy.app_https_proxy.id
#   port_range            = "443"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   network               = google_compute_network.vpc_network.id
#   network_tier          = "PREMIUM"

#   depends_on = [
#     google_compute_address.lb_ip,
#     google_compute_region_target_https_proxy.app_https_proxy,
#     google_compute_subnetwork.proxy_subnet
#   ]
# }
