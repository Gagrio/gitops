# GKE Cluster
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.zone

  # Use a single node pool
  initial_node_count       = var.node_count
  remove_default_node_pool = false

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "showcase"
    }

    tags = ["gitops-showcase"]
  }

  # Basic networking
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  # Disable features we don't need for showcase
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  deletion_protection = false
}
