namespace = "demo-webinar"

vm_name       = "demo-terraform"
vm_class_name = "generic"
vm_run_policy = "AlwaysOnUnlessStoppedManually"

vm_core_count        = 1
vm_cpu_core_fraction = "10%"
vm_ram_size          = "1Gi"

root_disk_name = "demo-terraform-root"
root_disk_size = "4Gi"
# root_disk_storage_class left unset: the cluster default StorageClass is used

# The project-wide image from 01-image/packer, the one the kubectl, kustomize and pool disks use too.
disk_data_source_type = "ObjectRef"
disk_object_ref_kind  = "VirtualImage"
disk_object_ref_name  = "demo-ubuntu-26-04-packer"

vm_labels = {
  "vm"         = "demo-terraform"
  "app"        = "ubuntu"
  "role"       = "web" # selector for maintenance runs
  "managed-by" = "terraform"
}

# Group in the inventory of d8 v ansible-inventory.
vm_annotations = {
  "ansible.deckhouse.io/groups" = "web"
}

disk_labels = {
  "vm"         = "demo-terraform"
  "disk"       = "root"
  "managed-by" = "terraform"
}

vm_restart_approval_mode = "Automatic"

# Exposure: Service + Ingress + Certificate + NetworkPolicy.
ingress_host = "demo-terraform.d8-virtualization.ru"

vm_provisioning_type      = "UserDataRef"
vm_cloud_init_secret_name = "demo-terraform"
vm_cloud_init_file        = "cfg/cloudinit.yaml"
