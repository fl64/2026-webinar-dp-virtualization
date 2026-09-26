packer {
  required_plugins {
    deckhouse-virtualization = {
      version = ">= 0.1.0"
      source  = "github.com/deckhouse/deckhouse-virtualization"
    }
  }
}

# Golden image: a cloud qcow in, a VirtualImage with nginx already installed out.
# The build runs inside the cluster: the plugin boots a temporary VM and reaches it through the
# portforward subresource with an ephemeral SSH key — no d8, kubectl or system ssh involved.

variable "namespace" {
  type    = string
  default = "demo-webinar"
}

variable "image_name" {
  type    = string
  default = "demo-packer"
}

variable "source_image_url" {
  type        = string
  description = "Cloud image to start from"
  default     = "https://mirror.yandex.ru/ubuntu-cloud-images/minimal/releases/resolute/release-20260723/ubuntu-26.04-minimal-cloudimg-amd64.img"
}

# Build machine sizing. Does not affect image contents, only how fast it builds.
variable "vm_class" {
  type    = string
  default = "generic"
}

variable "cpu_cores" {
  type    = number
  default = 1
}

variable "memory" {
  type    = string
  default = "1Gi"
}

# Keep the build VM and disk after the run, to investigate a failed build.
variable "keep_build_resources" {
  type    = bool
  default = false
}

source "deckhouse-virtualization" "ubuntu" {
  namespace = var.namespace

  disk {
    size = "4Gi"

    data_source {
      http {
        url = var.source_image_url
        # Checksum comes from the file the mirror publishes: a literal hash here would go stale
        # with the next image release. Not dirname(): it normalises the URL and collapses the
        # double slash after the scheme, leaving an unusable "https:/mirror...".
        checksum = "file:${trimsuffix(var.source_image_url, basename(var.source_image_url))}SHA256SUMS"
      }
    }
  }

  vm {
    vmclass     = var.vm_class
    cpu_cores   = var.cpu_cores
    memory_size = var.memory
  }

  image {
    name = var.image_name
  }

  ssh_username         = "packer"
  keep_build_resources = var.keep_build_resources
}

build {
  sources = ["source.deckhouse-virtualization.ubuntu"]

  # The point of baking: packages are installed once here instead of in every VM's cloud-init.
  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx",
      "sudo systemctl enable nginx",
    ]
  }

  # Default page, so a VM from this image is distinguishable from a stock nginx.
  # meta charset is required: nginx serves text/html without one.
  provisioner "file" {
    destination = "/tmp/index.html"
    content     = <<-HTML
      <!doctype html>
      <html lang="ru">
        <head><meta charset="utf-8"><title>packer</title></head>
        <body><h1>Hello, packer!</h1>
        <p>nginx уже стоял в образе — машина ничего не устанавливала при старте.</p></body>
      </html>
    HTML
  }

  # Generalize: without an emptied machine-id every VM from this image shares one, and DHCP
  # hands them the same address.
  provisioner "shell" {
    inline = [
      "sudo install -m 0644 /tmp/index.html /var/www/html/index.html",
      "sudo cloud-init clean --logs --seed",
      "sudo truncate -s0 /etc/machine-id",
    ]
  }
}
