terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = true
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = var.snippets_storage
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/cloud-init/gitlab.yaml", {
      ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
    })
    file_name = "gitlab-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "gitlab" {
  name      = "gitlab"
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = 80
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.vm_ip
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }
}

output "vm_ip" {
  value = var.vm_ip
}
