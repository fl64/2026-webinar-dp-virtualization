# Service -> Ingress -> Certificate plus a NetworkPolicy around the VM.
# VM labels are propagated to its pod, so an ordinary label selector matches the VM.
locals {
  expose_selector = { vm = var.vm_name }
}

resource "kubernetes_service_v1" "vm" {
  count = var.ingress_host == "" ? 0 : 1

  metadata {
    name      = var.vm_name
    namespace = var.namespace
    labels    = var.vm_labels
  }
  spec {
    selector = local.expose_selector
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "vm" {
  count = var.ingress_host == "" ? 0 : 1

  metadata {
    name      = var.vm_name
    namespace = var.namespace
    labels    = var.vm_labels
  }
  spec {
    ingress_class_name = var.ingress_class_name
    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.vm_name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = [var.ingress_host]
      secret_name = "${var.vm_name}-tls"
    }
  }
  depends_on = [kubernetes_service_v1.vm]
}

# cert-manager has no typed resource in the provider, hence kubernetes_manifest.
resource "kubernetes_manifest" "cert" {
  count = var.ingress_host == "" ? 0 : 1

  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = var.vm_name
      "namespace" = var.namespace
      "labels"    = var.vm_labels
    }
    "spec" = {
      "certificateOwnerRef" = false
      "dnsNames"            = [var.ingress_host]
      "issuerRef" = {
        "kind" = "ClusterIssuer"
        "name" = var.cert_cluster_issuer
      }
      "secretName" = "${var.vm_name}-tls"
    }
  }
}

resource "kubernetes_network_policy_v1" "vm" {
  count = var.ingress_host == "" ? 0 : 1

  metadata {
    name      = var.vm_name
    namespace = var.namespace
    labels    = var.vm_labels
  }
  spec {
    pod_selector {
      match_labels = local.expose_selector
    }
    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "d8-ingress-nginx" }
        }
        pod_selector {
          match_labels = { app = "controller" }
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    # 80/443 for cloud-init package downloads, 123 for NTP, 22 for the maintenance runner.
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
      ports {
        protocol = "UDP"
        port     = "123"
      }
    }

    # SSH from the maintenance runner pods.
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "d8-ansible" }
        }
      }
      ports {
        protocol = "TCP"
        port     = "22"
      }
    }
  }
}

output "vm_url" {
  description = "Application URL on the VM (empty when ingress_host is unset)"
  value       = var.ingress_host == "" ? "" : "https://${var.ingress_host}"
}
