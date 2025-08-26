# VMs Module Variables

variable "target_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "vm_configs" {
  description = "Configuration for VMs"
  type = map(object({
    vmid        = number
    name        = string
    desc        = string
    memory      = number
    cores       = number
    sockets     = number
    disk_size   = string
    disk_type   = string
    network_ip  = string
    tags        = list(string)
  }))
}

variable "template_name" {
  description = "VM template name for cloning"
  type        = string
}

variable "network_bridge" {
  description = "Network bridge for VMs"
  type        = string
}

variable "disk_storage" {
  description = "Storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "clone_wait" {
  description = "Wait time for clone operation"
  type        = number
  default     = 30
}

variable "agent" {
  description = "Enable QEMU agent"
  type        = number
  default     = 1
}

variable "boot" {
  description = "Boot order"
  type        = string
  default     = "order=scsi0;ide2;net0"
}

variable "scsihw" {
  description = "SCSI hardware type"
  type        = string
  default     = "virtio-scsi-pci"
}

variable "ci_user" {
  description = "Cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "ci_password" {
  description = "Cloud-init password"
  type        = string
  sensitive   = true
  default     = "ubuntu"
}

variable "ssh_keys" {
  description = "SSH public keys for VMs"
  type        = list(string)
  default     = []
}

variable "proxmox_host" {
  description = "Proxmox host IP for file uploads"
  type        = string
  default     = "127.0.0.1"
}

variable "default_packages" {
  description = "Default packages to install via cloud-init"
  type        = list(string)
  default     = [
    "curl",
    "wget",
    "git",
    "htop",
    "vim",
    "net-tools",
    "qemu-guest-agent"
  ]
}