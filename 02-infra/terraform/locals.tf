locals {
  vm_cloud_init_path = startswith(var.vm_cloud_init_file, "/") ? var.vm_cloud_init_file : "${path.module}/${var.vm_cloud_init_file}"
  vm_user_data       = length(var.vm_provisioning_userdata) > 0 ? var.vm_provisioning_userdata : (length(var.vm_cloud_init_file) > 0 ? file(local.vm_cloud_init_path) : "")
}
