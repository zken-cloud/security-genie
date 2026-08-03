data "google_compute_default_service_account" "default" {}

resource "google_cloud_run_v2_service" "agent" {
  name     = "agent"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = data.google_compute_default_service_account.default.email

    containers {
      image = "gcr.io/cloudrun/hello:latest"

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.agent_db.public_ip_address
      }

      env {
        name  = "DB_USER"
        value = google_sql_user.agent.name
      }

      env {
        name  = "DB_PASSWORD"
        value = var.db_password
      }
    }
  }
}

# The agent is called from the internet via the load balancer
resource "google_cloud_run_v2_service_iam_member" "agent_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.agent.location
  name     = google_cloud_run_v2_service.agent.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
