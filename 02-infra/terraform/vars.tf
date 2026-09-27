variable "namespace" {
  description = "Namespace of the VirtualMachineDisk"
}

variable "root_disk_name" {
  description = "Name of the VirtualMachineDisk"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.root_disk_name)) && length(var.root_disk_name) <= 60
    error_message = "root_disk_name must be a string starting with a lowercase letter, followed by lowercase letters, digits, or hyphens, with a maximum length of 60 characters"
  }
}

variable "root_disk_size" {
  description = "Size of the PersistentVolumeClaim. Optional - if empty, size will not be added"
  type        = string
  default     = ""
  validation {
    condition     = var.root_disk_size == "" || can(regex("^(\\+|-)?(([0-9]+(\\.[0-9]*)?)|(\\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\\+|-)?(([0-9]+(\\.[0-9]*)?)|(\\.[0-9]+))))?$", var.root_disk_size))
    error_message = "root_disk_size must be a valid Kubernetes quantity format (e.g., '20Gi', '100G', '512Mi'). Supported units: Ki, Mi, Gi, Ti, Pi, Ei, k, M, G, T, P, E, n, u, m"
  }
}

variable "root_disk_storage_class" {
  description = "Storage class for the PersistentVolumeClaim. Optional - if empty, storageClassName will not be added"
  type        = string
  default     = ""
}

variable "disk_http_url" {
  description = "HTTP URL for VirtualDisk dataSource"
  type        = string
  default     = ""
  validation {
    condition     = var.disk_http_url == "" || can(regex("^https?://", var.disk_http_url))
    error_message = "disk_http_url must be a valid HTTP or HTTPS URL starting with http:// or https://"
  }
}

variable "disk_data_source_type" {
  description = "VirtualDisk dataSource type"
  type        = string
  default     = "HTTP"
  validation {
    condition     = contains(["HTTP", "ObjectRef"], var.disk_data_source_type)
    error_message = "disk_data_source_type must be either 'HTTP' or 'ObjectRef'"
  }
}

variable "disk_object_ref_kind" {
  description = "Kind for ObjectRef VirtualDisk dataSource"
  type        = string
  default     = ""
}

variable "disk_object_ref_name" {
  description = "Name for ObjectRef VirtualDisk dataSource"
  type        = string
  default     = ""
}

variable "vm_name" {
  description = "Name of the VirtualMachine"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.vm_name)) && length(var.vm_name) <= 63
    error_message = "vm_name must be a string starting with a lowercase letter, followed by lowercase letters, digits, or hyphens, with a maximum length of 63 characters"
  }
}

variable "vm_core_count" {
  description = "VM CPU count"
  type        = number
  validation {
    condition     = var.vm_core_count >= 1 && var.vm_core_count <= 1024
    error_message = "vm_core_count must be between 1 and 1024"
  }
}

variable "vm_cpu_core_fraction" {
  description = "VM CPU corefraction. Optional - if empty, coreFraction will not be added"
  type        = string
  default     = ""
  validation {
    condition     = var.vm_cpu_core_fraction == "" || can(regex("^([1-9]|[1-9][0-9]|100)%$", var.vm_cpu_core_fraction))
    error_message = "vm_cpu_core_fraction must be a string in percentage format from 1% to 100% (e.g., '50%') or empty"
  }
}

variable "vm_ram_size" {
  description = "VM RAM size"
  type        = string
  default     = "512Mi"
  validation {
    condition     = can(regex("^(\\+|-)?(([0-9]+(\\.[0-9]*)?)|(\\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\\+|-)?(([0-9]+(\\.[0-9]*)?)|(\\.[0-9]+))))?$", var.vm_ram_size))
    error_message = "vm_ram_size must be a valid Kubernetes quantity format (e.g., '512Mi', '2Gi', '1G', '1024'). Supported units: Ki, Mi, Gi, Ti, Pi, Ei, k, M, G, T, P, E, n, u, m"
  }
}

variable "vm_provisioning_userdata" {
  description = "User data for the VirtualMachine (cloud-init configuration). Optional - if empty, provisioning section will not be added"
  type        = string
  default     = ""
}

variable "vm_cloud_init_file" {
  description = "Path to cloud-init userdata file. Relative paths are resolved from this Terraform module"
  type        = string
  default     = ""
}

variable "vm_cloud_init_secret_name" {
  description = "Secret name used by UserDataRef provisioning"
  type        = string
  default     = "cloud-init"
}

variable "vm_provisioning_type" {
  description = "Provisioning mode for the VirtualMachine"
  type        = string
  default     = "UserData"
  validation {
    condition     = contains(["UserData", "UserDataRef"], var.vm_provisioning_type)
    error_message = "vm_provisioning_type must be either 'UserData' or 'UserDataRef'"
  }
}

variable "vm_class_name" {
  description = "Name of the VirtualMachineClass resource. Optional - if empty, virtualMachineClassName will not be added"
  type        = string
  default     = ""
}

variable "vm_labels" {
  description = "Labels for the VirtualMachine"
  type        = map(string)
  default     = {}
}

variable "disk_labels" {
  description = "Labels for the VirtualDisk"
  type        = map(string)
  default     = {}
}

variable "vm_restart_approval_mode" {
  description = "Restart approval mode for the VirtualMachine disruptions. Default is Manual"
  type        = string
  default     = "Manual"
  validation {
    condition     = contains(["Manual", "Automatic"], var.vm_restart_approval_mode)
    error_message = "vm_restart_approval_mode must be either 'Manual' or 'Automatic'"
  }
}

variable "vm_bootloader" {
  description = "Bootloader type for the VirtualMachine. Optional - if empty, bootloader will not be added"
  type        = string
  default     = ""
  validation {
    condition     = var.vm_bootloader == "" || contains(["BIOS", "EFI", "UEFI"], var.vm_bootloader)
    error_message = "vm_bootloader must be one of 'BIOS', 'EFI', 'UEFI', or empty"
  }
}

variable "vm_run_policy" {
  description = "Run policy for the VirtualMachine. Optional - if empty, runPolicy will not be added"
  type        = string
  default     = ""
}

variable "ingress_host" {
  description = "Hostname for the Ingress/Certificate. Optional - if empty, Service/Ingress/Certificate/NetworkPolicy are not created"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "IngressClass for the Ingress"
  type        = string
  default     = "nginx"
}

variable "cert_cluster_issuer" {
  description = "cert-manager ClusterIssuer used to issue the TLS certificate"
  type        = string
  default     = "letsencrypt"
}
