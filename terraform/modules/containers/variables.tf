# Containers Module Variables

variable "target_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "container_id" {
  description = "Container ID"
  type        = number
}

variable "container_name" {
  description = "Container hostname"
  type        = string
}

variable "container_memory" {
  description = "Container memory in MB"
  type        = number
  default     = 4096
}

variable "container_cores" {
  description = "Container CPU cores"
  type        = number
  default     = 2
}

variable "container_storage" {
  description = "Container storage size"
  type        = string
  default     = "20G"
}

variable "container_password" {
  description = "Container root password"
  type        = string
  sensitive   = true
  default     = "proxmox123"
}

variable "network_bridge" {
  description = "Network bridge for container"
  type        = string
}

variable "network_ip" {
  description = "Container IP address with CIDR"
  type        = string
}

variable "template_storage" {
  description = "Storage for container templates"
  type        = string
  default     = "local"
}

variable "ssh_keys" {
  description = "SSH public keys for container access"
  type        = list(string)
  default     = []
}

variable "container_tags" {
  description = "Tags for container organization"
  type        = list(string)
  default     = ["infrastructure", "management"]
}

variable "automation_tools" {
  description = "List of automation tools to install"
  type        = list(string)
  default     = ["terraform", "ansible", "packer", "git", "python3"]
}