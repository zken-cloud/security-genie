resource "google_service_account" "agent_sa" {
  account_id   = "agent-sa"
  display_name = "Support agent service account"
}

# Key for the on-prem integration job
resource "google_service_account_key" "agent_sa_key" {
  service_account_id = google_service_account.agent_sa.name
}

resource "google_project_iam_member" "agent_sa_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.agent_sa.email}"
}
