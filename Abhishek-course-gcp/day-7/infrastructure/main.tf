#task 1 create startup.sh
#task 2: create instance template:


#actual template
resource "google_compute_instance_template" "web-template" {
  name                    = "web-template-day-7"
  machine_type            = "e2-micro"
  tags                    = ["http-server"] #applied from target tags
  metadata_startup_script = file("startup.sh")

  lifecycle {
    prevent_destroy = false
  }


  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }



  network_interface {
    network = "default"
    access_config {
      //  IPs via which this instance can be accessed via the Internet --> EVERYONE in this case
    }
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true #google def:  being replaced or displaced by something of higher priority or necessity
    automatic_restart  = false
  }
}




#task 3: Managed Instance Group Across 3 Zones
resource "google_compute_region_instance_group_manager" "web-mig" {
  name               = "web-mig-day-7"
  description        = "Managed Instance Group for web servers across multiple zones"
  base_instance_name = "web-instance"
  region             = "us-central1"
  target_size        = 2

  auto_healing_policies {
    health_check      = google_compute_health_check.web_health_check.id
    initial_delay_sec = 300
  }
  version {
    instance_template = google_compute_instance_template.web-template.self_link
  }

  named_port {
    name = "http"
    port = 80
  }

  distribution_policy_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}

#auto scaling
resource "google_compute_region_autoscaler" "web_autoscaler" {
  name   = "web-autoscaler"
  region = "us-central1"
  target = google_compute_region_instance_group_manager.web-mig.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 60

    cpu_utilization {
      target = 0.6 #60 % usage
    }
  }
}


#TASK-4 allow http-TRAFFIC 
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

#taks 5
#health check mentioned in official site -> best for autohealing like automatically check if healthy or remove and recreate if not
resource "google_compute_health_check" "web_health_check" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  log_config {
    enable = true
  }

  http_health_check {
    request_path = "/"
    port         = "80"
  }
}

#task 6: HTTP Load Balancer Components - 

#i didnt understand this part clearly so used CHATGPT HELP

//------------------------------------------------------------------------------------

# HOW IT WORKS: Internet -> Forwarding Rule -> HTTP Proxy -> URL Map -> Backend Service -> Instance Group

#similar to (AWS Target Groups)

# BACKEND SERVICE: The "brain" that decides which instances get traffic
resource "google_compute_backend_service" "web_backend" {
  name                  = "web-backend-service"                             # Name of the backend service
  protocol              = "HTTP"                                            # Protocol used (HTTP/HTTPS)
  port_name             = "http"                                            # Named port for communication
  load_balancing_scheme = "EXTERNAL"                                        # External (internet-facing) load balancer
  timeout_sec           = 30                                                # How long to wait for backend response
  health_checks         = [google_compute_health_check.web_health_check.id] # Health check to monitor instances

  backend {
    group           = google_compute_region_instance_group_manager.web-mig.instance_group # Which instance group to send traffic to
    balancing_mode  = "UTILIZATION"                                                       # Distribute based on CPU utilization
    capacity_scaler = 1.0                                                                 # Use 100% of instance group capacity
  }
}

#task - 7 and afterwards

# URL MAP: Traffic router - decides which backend service handles which URLs
resource "google_compute_url_map" "web_url_map" {
  name            = "web-url-map"                                 # Name of URL map
  default_service = google_compute_backend_service.web_backend.id # Default backend for all traffic (since we have only one)
  # You can add path_matcher here for different URLs -> different backends
  # Example: /api/* -> api-backend, /images/* -> image-backend
}
#can we omit url_map? cause we have 'default' thing:
#ans: nope: GCP needs to know where to send traffic

#similar to (AWS ALB Rules) 



//-------------------------------
# HTTP PROXY: Terminates HTTP connections and forwards to backend
resource "google_compute_target_http_proxy" "web_proxy" {
  name    = "web-http-proxy"                      # Name of HTTP proxy
  url_map = google_compute_url_map.web_url_map.id # Which URL map to use for routing decisions
  # This is where SSL termination would happen for HTTPS
}


# FORWARDING RULE: The "front door" - provides external IP address
resource "google_compute_global_forwarding_rule" "web_forwarding_rule" {
  name       = "web-forwarding-rule"                         # Name of forwarding rule
  target     = google_compute_target_http_proxy.web_proxy.id # Which proxy handles the traffic
  port_range = "80"                                          # Which port accepts traffic (80 for HTTP)
  # This creates the external IP that users connect to
  # Traffic flow: User -> This IP:80 -> HTTP Proxy -> URL Map -> Backend Service -> Your Instances
}


# Output the external IP address
output "load_balancer_ip" {
  value = google_compute_global_forwarding_rule.web_forwarding_rule.ip_address
}


#curl http://$(terraform output -raw load_balancer_ip)
#result:
#Welcome to Day-7 MIG Demo - web-instance-81kn
#Welcome to Day-7 MIG Demo - web-instance-02jp

#Dont panic after applying it'll take some time to be healthy