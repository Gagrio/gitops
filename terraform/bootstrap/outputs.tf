output "apis_enabled" {
  description = "APIs that were enabled"
  value       = [for api in google_project_service.apis : api.service]
}
