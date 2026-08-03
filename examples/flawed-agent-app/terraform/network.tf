resource "google_compute_network" "agent_vpc" {
  name                    = "agent-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "agent_subnet" {
  name          = "agent-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.agent_vpc.id
}

# Let ops reach the machines
resource "google_compute_firewall" "allow_admin" {
  name    = "allow-admin"
  network = google_compute_network.agent_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }

  source_ranges = ["0.0.0.0/0"]
}
