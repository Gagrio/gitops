# GKE Cluster
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.zone

  # Remove the default node pool after cluster creation
  initial_node_count       = 1
  remove_default_node_pool = true

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

# Managed Node Pool
resource "google_container_node_pool" "primary" {
  name       = "primary-pool"
  cluster    = google_container_cluster.main.id
  node_count = var.node_count

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

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Kubernetes Namespaces
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      environment = "showcase"
    }
  }

  depends_on = [google_container_node_pool.primary]
}
