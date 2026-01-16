variable "proxmox_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "template_id" {
  description = "VM template ID to clone from"
  type        = number
  default     = 9000

  validation {
    condition     = var.template_id >= 100 && var.template_id <= 999999999
    error_message = "Template ID must be between 100 and 999999999 (Proxmox valid range)."
  }
}

variable "vm_id" {
  description = "VM ID for GitLab"
  type        = number
  default     = 1000

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999 (Proxmox valid range)."
  }
}

variable "vm_ip" {
  description = "Static IP for GitLab VM (CIDR notation)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vm_ip, 0))
    error_message = "vm_ip must be a valid IP address in CIDR notation (e.g., 192.168.68.50/24)."
  }
}

variable "gateway" {
  description = "Network gateway"
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$", var.gateway))
    error_message = "gateway must be a valid IP address (e.g., 192.168.68.1)."
  }
}

variable "storage" {
  description = "Storage for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "snippets_storage" {
  description = "Storage for cloud-init snippets"
  type        = string
  default     = "local"
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
