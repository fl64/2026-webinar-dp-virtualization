packer {
  required_plugins {
    deckhouse-virtualization = {
      version = ">= 0.1.0"
      source  = "github.com/deckhouse/deckhouse-virtualization"
    }
  }
}

# The project image: Ubuntu Server installed from the ISO of step 1 (00-prep/vi-iso.yaml),
# made into a cloud image by scripts/ and captured as a VirtualImage in the project.
# Every VM of the demo starts from it.

variable "namespace" {
  type    = string
  default = "demo-webinar"
}

variable "image_name" {
  type    = string
  default = "ubuntu-26-04-packer"
}

# Build machine sizing. Does not affect image contents, only how fast it builds.
variable "vm_class" {
  type    = string
  default = "generic"
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = string
  default = "4Gi"
}

source "deckhouse-virtualization" "ubuntu" {
  namespace = var.namespace

  iso {
    object_ref {
      kind = "VirtualImage"
      name = "demo-iso"
    }
  }

  disk {
    # The image occupies the full size of this disk in DVCR, so it is kept small; the guest grows
    # the root filesystem into whatever disk a VM gets. Sized after `df` printed by 80-verify.sh.
    size = "3Gi"
  }

  vm {
    vmclass     = var.vm_class
    cpu_cores   = var.cpu_cores
    memory_size = var.memory
  }

  # The answers travel on the CIDATA medium only: handing them to `vm.user_data` as well makes the
  # platform attach cloud-init as a second disk, and curtin then tries to put GRUB on it.
  answer_label = "CIDATA"
  answer_files = {
    "user-data" = file("autoinstall.yaml")
    "meta-data" = "instance-id: packer-build\nlocal-hostname: packer-build\n"
  }

  # Without `autoinstall` on the kernel command line subiquity asks "Continue with autoinstall?
  # (yes|no)" once the live system is up; the answer is typed over VNC.
  boot_wait    = "3m"
  boot_command = ["yes<enter>"]

  image {
    name = var.image_name
  }

  ssh_username = "packer"
  # Keeps the session alive while apt produces no output.
  ssh_keep_alive_interval = "10s"
  ssh_timeout             = "30m"
  install_timeout         = "60m"
  state_timeout           = "60m"
}

build {
  sources = ["source.deckhouse-virtualization.ubuntu"]

  provisioner "file" {
    source      = "${path.root}/scripts/00-lib.sh"
    destination = "/tmp/packer-lib.sh"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/files/sshd-hardening.conf"
    destination = "/tmp/sshd-hardening.conf"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/files/sysctl-hardening.conf"
    destination = "/tmp/sysctl-hardening.conf"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    # The scripts are idempotent, so a dropped SSH session costs a rerun of the step, not the build.
    max_retries = 2
    scripts = [
      "${path.root}/scripts/10-packages.sh",
      "${path.root}/scripts/20-services.sh",
      "${path.root}/scripts/30-hardening.sh",
      "${path.root}/scripts/40-cloud.sh",
      "${path.root}/scripts/80-verify.sh",
      "${path.root}/scripts/90-sysprep.sh",
    ]
  }
}
