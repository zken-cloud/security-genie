output "lb_ip_address" {
  description = "Public IP of the external HTTP load balancer"
  value       = google_compute_global_forwarding_rule.agent_http.ip_address
}

output "cloud_run_uri" {
  description = "URI of the agent Cloud Run service"
  value       = google_cloud_run_v2_service.agent.uri
}

output "cloudsql_public_ip" {
  description = "Public IP of the agent Cloud SQL instance"
  value       = google_sql_database_instance.agent_db.public_ip_address
}
