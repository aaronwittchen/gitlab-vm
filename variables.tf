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

# =============================================================================
# Talos Runner Variables
# =============================================================================

variable "runner_vm_id" {
  description = "VM ID for Talos runner"
  type        = number
  default     = 1001

  validation {
    condition     = var.runner_vm_id >= 100 && var.runner_vm_id <= 999999999
    error_message = "VM ID must be between 100 and 999999999."
  }
}

variable "runner_hostname" {
  description = "Hostname for the Talos runner node"
  type        = string
  default     = "talos-runner"
}

variable "runner_cluster_name" {
  description = "Name of the Talos K8s cluster"
  type        = string
  default     = "gitlab-runner"
}

variable "runner_ip" {
  description = "Final static IP address for Talos runner (without CIDR)"
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$", var.runner_ip))
    error_message = "runner_ip must be a valid IP address (e.g., 192.168.68.51)."
  }
}

variable "runner_dhcp_ip" {
  description = "Initial DHCP IP for Talos runner (check Proxmox console after first boot)"
  type        = string
  default     = ""
}

variable "runner_ip_cidr" {
  description = "IP address for Talos runner with CIDR notation"
  type        = string

  validation {
    condition     = can(cidrhost(var.runner_ip_cidr, 0))
    error_message = "runner_ip_cidr must be a valid IP in CIDR notation (e.g., 192.168.68.51/24)."
  }
}

variable "runner_cpu_cores" {
  description = "Number of CPU cores for runner"
  type        = number
  default     = 4
}

variable "runner_memory" {
  description = "Memory in MB for runner"
  type        = number
  default     = 16384
}

variable "runner_disk_size" {
  description = "Disk size in GB for runner"
  type        = number
  default     = 80
}

variable "nameservers" {
  description = "DNS nameservers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# =============================================================================
# GitLab Runner Variables
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.example.com"
}

variable "gitlab_runner_token" {
  description = "GitLab Runner registration token (leave empty to skip runner installation)"
  type        = string
  default     = ""
  sensitive   = true
}
