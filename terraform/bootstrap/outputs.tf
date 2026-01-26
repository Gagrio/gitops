output "state_bucket" {
  description = "GCS bucket for Terraform state"
  value       = google_storage_bucket.tfstate.name
}

output "apis_enabled" {
  description = "APIs that were enabled"
  value       = [for api in google_project_service.apis : api.service]
}
