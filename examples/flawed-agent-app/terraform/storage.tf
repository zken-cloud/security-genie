resource "google_storage_bucket" "agent_exports" {
  name          = "${var.project_id}-agent-exports"
  location      = "US"
  force_destroy = true
}

# Support-export links are shared with partners
resource "google_storage_bucket_iam_member" "exports_viewer" {
  bucket = google_storage_bucket.agent_exports.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
