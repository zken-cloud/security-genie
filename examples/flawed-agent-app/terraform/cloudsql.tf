resource "google_sql_database_instance" "agent_db" {
  name                = "agent-db"
  database_version    = "POSTGRES_15"
  region              = var.region
  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true

      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }
  }
}

resource "google_sql_user" "agent" {
  name     = "agent"
  instance = google_sql_database_instance.agent_db.name
  password = var.db_password
}
