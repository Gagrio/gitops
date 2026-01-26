# Flux bootstrap
resource "flux_bootstrap_git" "this" {
  depends_on = [
    google_container_node_pool.primary,
    kubernetes_namespace.monitoring
  ]

  embedded_manifests = true
  path               = var.flux_target_path

  # Only deploy required components (excludes notification-controller)
  components = [
    "source-controller",
    "kustomize-controller",
    "helm-controller"
  ]

  # Image automation controllers - enable these if you need automatic container
  # image updates. They scan container registries for new tags and can auto-commit
  # updated image references back to Git. Requires ImageRepository and
  # ImageUpdateAutomation CRDs. Disabled to save resources on small clusters.
  # components_extra = [
  #   "image-reflector-controller",
  #   "image-automation-controller"
  # ]
}
