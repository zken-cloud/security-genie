resource "google_compute_region_network_endpoint_group" "agent_neg" {
  name                  = "agent-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.agent.name
  }
}

resource "google_compute_backend_service" "agent_backend" {
  name                  = "agent-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.agent_neg.id
  }
}

resource "google_compute_url_map" "agent_url_map" {
  name            = "agent-url-map"
  default_service = google_compute_backend_service.agent_backend.id
}

resource "google_compute_target_http_proxy" "agent_http_proxy" {
  name    = "agent-http-proxy"
  url_map = google_compute_url_map.agent_url_map.id
}

resource "google_compute_global_forwarding_rule" "agent_http" {
  name                  = "agent-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.agent_http_proxy.id
}
