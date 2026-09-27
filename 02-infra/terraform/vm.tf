

resource "kubernetes_secret_v1" "cloud_init" {
  count = var.vm_provisioning_type == "UserDataRef" && length(local.vm_user_data) > 0 ? 1 : 0

  metadata {
    name      = var.vm_cloud_init_secret_name
    namespace = var.namespace
  }

  type = "provisioning.virtualization.deckhouse.io/cloud-init"
  data = {
    userdata = local.vm_user_data
  }

  wait_for_service_account_token = false

}

resource "kubernetes_manifest" "vm" {
  manifest = {
    "apiVersion" = "virtualization.deckhouse.io/v1alpha2"
    "kind"       = "VirtualMachine"
    "metadata" = {
      "name"      = var.vm_name
      "namespace" = var.namespace
      "labels"    = var.vm_labels
    }
    "spec" = merge(
      {
        "blockDeviceRefs" = [
          {
            "kind" = "VirtualDisk"
            "name" = kubernetes_manifest.vd.manifest.metadata.name
          },
        ]
        "cpu" = merge(
          {
            "cores" = var.vm_core_count
          },
          length(var.vm_cpu_core_fraction) > 0 ? {
            "coreFraction" = var.vm_cpu_core_fraction
          } : {}
        )
        "memory" = {
          "size" = var.vm_ram_size
        }
        "disruptions" = {
          "restartApprovalMode" = var.vm_restart_approval_mode
        }
      },
      length(var.vm_run_policy) > 0 ? {
        "runPolicy" = var.vm_run_policy
      } : {},
      length(var.vm_bootloader) > 0 ? {
        "bootloader" = var.vm_bootloader
      } : {},
      length(var.vm_class_name) > 0 ? {
        "virtualMachineClassName" = var.vm_class_name
      } : {},
      var.vm_provisioning_type == "UserData" && length(local.vm_user_data) > 0 ? {
        "provisioning" = {
          "type"     = "UserData"
          "userData" = local.vm_user_data
        }
      } : {},
      var.vm_provisioning_type == "UserDataRef" ? {
        "provisioning" = {
          "type" = "UserDataRef"
          "userDataRef" = {
            "kind" = "Secret"
            "name" = var.vm_cloud_init_secret_name
          }
        }
      } : {}
    )
  }
  depends_on = [kubernetes_secret_v1.cloud_init]
  wait {
    fields = {
      "status.phase" = "Running"
    }
  }
  timeouts {
    create = "10m"
    update = "1m"
    delete = "1m"
  }
}

output "vm_name" {
  description = "The name of the VirtualMachine"
  value       = kubernetes_manifest.vm.manifest.metadata.name
}

data "kubernetes_resource" "vm_status" {
  api_version = "virtualization.deckhouse.io/v1alpha2"
  kind        = "VirtualMachine"
  metadata {
    name      = var.vm_name
    namespace = var.namespace
  }
  depends_on = [kubernetes_manifest.vm]
}

output "vm_ip_address" {
  description = "The IP address of the VirtualMachine"
  value       = data.kubernetes_resource.vm_status.object.status.ipAddress
}
