# Flux bootstrap
resource "flux_bootstrap_git" "this" {
  depends_on = [google_container_cluster.main]

  embedded_manifests = true
  path               = var.flux_target_path
  branch             = "master"

  components_extra = [
    "image-reflector-controller",
    "image-automation-controller"
  ]
}
