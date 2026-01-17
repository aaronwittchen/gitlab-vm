# =============================================================================
# Talos Linux GitLab Runner Cluster (Single Node)
# =============================================================================

locals {
  talos_version = "v1.12.1"
  # Schematic includes qemu-guest-agent extension for Proxmox
  talos_schematic = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
  talos_iso_url   = "https://factory.talos.dev/image/${local.talos_schematic}/${local.talos_version}/metal-amd64.iso"
}

# -----------------------------------------------------------------------------
# Download Talos ISO to Proxmox
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.snippets_storage  # Must be file-based storage, not LVM
  node_name    = var.proxmox_node
  url          = local.talos_iso_url
  file_name    = "talos-${local.talos_version}-metal-amd64.iso"
}

# -----------------------------------------------------------------------------
# Talos Machine Secrets (stored in state, generate once)
# -----------------------------------------------------------------------------
resource "talos_machine_secrets" "runner" {}

# -----------------------------------------------------------------------------
# Talos Machine Configuration
# -----------------------------------------------------------------------------
data "talos_machine_configuration" "runner" {
  cluster_name     = var.runner_cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.runner_ip}:6443"
  machine_secrets  = talos_machine_secrets.runner.machine_secrets
}

data "talos_client_configuration" "runner" {
  cluster_name         = var.runner_cluster_name
  client_configuration = talos_machine_secrets.runner.client_configuration
  endpoints            = [var.runner_ip]
  nodes                = [var.runner_ip]
}

# -----------------------------------------------------------------------------
# Proxmox VM for Talos Runner
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "talos_runner" {
  name      = var.runner_hostname
  node_name = var.proxmox_node
  vm_id     = var.runner_vm_id

  machine = "q35"
  bios    = "seabios"

  cpu {
    cores = var.runner_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.runner_memory
  }

  agent {
    enabled = false
  }

  # Boot from ISO
  cdrom {
    file_id = proxmox_virtual_environment_download_file.talos_iso.id
  }

  # Empty disk for Talos to install to
  disk {
    datastore_id = var.storage
    interface    = "virtio0"
    size         = var.runner_disk_size
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }

  # Don't start automatically - we need to apply config first
  started = true
}

# -----------------------------------------------------------------------------
# Apply Talos Configuration
# -----------------------------------------------------------------------------
resource "talos_machine_configuration_apply" "runner" {
  client_configuration        = talos_machine_secrets.runner.client_configuration
  machine_configuration_input = data.talos_machine_configuration.runner.machine_configuration
  # Use DHCP IP for initial apply if set, otherwise use static IP
  node                        = var.runner_dhcp_ip != "" ? var.runner_dhcp_ip : var.runner_ip

  config_patches = [
    templatefile("${path.module}/talos/machine-config-patch.yaml.tftpl", {
      ip_cidr     = var.runner_ip_cidr
      gateway     = var.gateway
      nameservers = var.nameservers
    })
  ]

  depends_on = [proxmox_virtual_environment_vm.talos_runner]
}

# -----------------------------------------------------------------------------
# Bootstrap Talos Cluster
# -----------------------------------------------------------------------------
resource "talos_machine_bootstrap" "runner" {
  client_configuration = talos_machine_secrets.runner.client_configuration
  node                 = var.runner_ip

  depends_on = [talos_machine_configuration_apply.runner]
}

# -----------------------------------------------------------------------------
# Get Kubeconfig
# -----------------------------------------------------------------------------
resource "talos_cluster_kubeconfig" "runner" {
  client_configuration = talos_machine_secrets.runner.client_configuration
  node                 = var.runner_ip

  depends_on = [talos_machine_bootstrap.runner]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "runner_vm_id" {
  description = "VM ID of the Talos runner"
  value       = proxmox_virtual_environment_vm.talos_runner.vm_id
}

output "runner_ip" {
  description = "IP address of the Talos runner"
  value       = var.runner_ip
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.runner.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig for the runner cluster"
  value       = talos_cluster_kubeconfig.runner.kubeconfig_raw
  sensitive   = true
}

# =============================================================================
# Helm Provider Configuration
# =============================================================================

provider "helm" {
  kubernetes {
    host                   = talos_cluster_kubeconfig.runner.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.runner.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.runner.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.runner.kubernetes_client_configuration.ca_certificate)
  }
}

# -----------------------------------------------------------------------------
# Cilium CNI
# -----------------------------------------------------------------------------
resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.17.0"

  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  set {
    name  = "k8sServiceHost"
    value = var.runner_ip
  }

  set {
    name  = "k8sServicePort"
    value = "6443"
  }

  # Talos-specific settings
  set {
    name  = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }

  set {
    name  = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }

  set {
    name  = "cgroup.autoMount.enabled"
    value = "false"
  }

  set {
    name  = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }

  depends_on = [talos_cluster_kubeconfig.runner]
}

# -----------------------------------------------------------------------------
# GitLab Runner
# -----------------------------------------------------------------------------
resource "helm_release" "gitlab_runner" {
  count = var.gitlab_runner_token != "" ? 1 : 0

  name             = "gitlab-runner"
  namespace        = "gitlab-runner"
  create_namespace = true
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-runner"
  version          = "0.71.0"

  set {
    name  = "gitlabUrl"
    value = var.gitlab_url
  }

  set_sensitive {
    name  = "runnerToken"
    value = var.gitlab_runner_token
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  # Run builds in Kubernetes
  set {
    name  = "runners.executor"
    value = "kubernetes"
  }

  depends_on = [helm_release.cilium]
}
