

resource "kubernetes_manifest" "vd" {
  manifest = {
    "apiVersion" = "virtualization.deckhouse.io/v1alpha2"
    "kind"       = "VirtualDisk"
    "metadata" = {
      "name"      = var.root_disk_name
      "namespace" = var.namespace
      "labels"    = var.disk_labels
    }
    "spec" = merge(
      {
        "dataSource" = merge(
          {
            "type" = var.disk_data_source_type
          },
          var.disk_data_source_type == "HTTP" ? {
            "http" = {
              "url" = var.disk_http_url
            }
          } : {},
          var.disk_data_source_type == "ObjectRef" ? {
            "objectRef" = {
              "kind" = var.disk_object_ref_kind
              "name" = var.disk_object_ref_name
            }
          } : {}
        )
      },
      (length(var.root_disk_size) > 0 || length(var.root_disk_storage_class) > 0) ? {
        "persistentVolumeClaim" = {
          for k, v in {
            "size"             = var.root_disk_size
            "storageClassName" = var.root_disk_storage_class
          } : k => v if length(v) > 0
        }
      } : {}
    )
  }
  timeouts {
    create = "10m"
    update = "1m"
    delete = "1m"
  }
}

output "disk_name" {
  description = "The name of the VirtualMachineDisk"
  value       = kubernetes_manifest.vd.manifest.metadata.name
}
