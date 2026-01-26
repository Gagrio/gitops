variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the cluster"
  type        = string
  default     = "europe-west1-b"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "gitops-showcase"
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 1
}

variable "github_owner" {
  description = "GitHub username or organization"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
  default     = "gitops"
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "flux_target_path" {
  description = "Path in the repository for Flux to sync"
  type        = string
  default     = "kubernetes"
}
