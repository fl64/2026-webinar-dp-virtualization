namespace = "demo-webinar"

vm_name       = "demo-tf"
vm_class_name = "generic"
vm_run_policy = "AlwaysOnUnlessStoppedManually"

vm_core_count        = 1
vm_cpu_core_fraction = "10%"
vm_ram_size          = "1Gi"

root_disk_name = "demo-tf-root"
root_disk_size = "10Gi"
# root_disk_storage_class left unset: the cluster default StorageClass is used

# The project-wide image from project/vi.yaml, the one the kubectl, kustomize and pool disks use too.
disk_data_source_type = "ObjectRef"
disk_object_ref_kind  = "VirtualImage"
disk_object_ref_name  = "demo-ubuntu"

vm_labels = {
  "vm"         = "demo-tf"
  "app"        = "ubuntu"
  "role"       = "demo" # selector for maintenance runs
  "managed-by" = "terraform"
}

disk_labels = {
  "vm"         = "demo-tf"
  "disk"       = "root"
  "managed-by" = "terraform"
}

vm_restart_approval_mode = "Automatic"

# Exposure: Service + Ingress + Certificate + NetworkPolicy.
ingress_host = "demo-tf.pt.dvp.flant.dev"

vm_provisioning_type      = "UserDataRef"
vm_cloud_init_secret_name = "demo-tf"
vm_cloud_init_file        = "cfg/cloudinit.yaml"
