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
}

variable "vm_id" {
  description = "VM ID for GitLab"
  type        = number
  default     = 200
}

variable "vm_ip" {
  description = "Static IP for GitLab VM (CIDR notation)"
  type        = string
}

variable "gateway" {
  description = "Network gateway"
  type        = string
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
