# Proxmox Connection Variables
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://localhost:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Disable TLS verification for Proxmox API"
  type        = bool
  default     = true
}

# SDN Configuration Variables
variable "sdn_zone_name" {
  description = "Name of the SDN zone"
  type        = string
  default     = "infrastructure-zone"
}

variable "management_vnet" {
  description = "Management VNET name"
  type        = string
  default     = "management-net"
}

variable "infrastructure_vnet" {
  description = "Infrastructure VNET name"
  type        = string
  default     = "infrastructure-net"
}

variable "services_vnet" {
  description = "Services VNET name"
  type        = string
  default     = "services-net"
}

variable "management_subnet" {
  description = "Management subnet CIDR"
  type        = string
  default     = "10.100.1.0/24"
}

variable "infrastructure_subnet" {
  description = "Infrastructure subnet CIDR"
  type        = string
  default     = "10.100.2.0/24"
}

variable "services_subnet" {
  description = "Services subnet CIDR"
  type        = string
  default     = "10.100.3.0/24"
}

variable "dhcp_ranges" {
  description = "DHCP ranges for each network"
  type = map(object({
    start = string
    end   = string
  }))
  default = {
    management = {
      start = "10.100.1.100"
      end   = "10.100.1.200"
    }
    infrastructure = {
      start = "10.100.2.100"
      end   = "10.100.2.200"
    }
    services = {
      start = "10.100.3.100"
      end   = "10.100.3.200"
    }
  }
}

# Management Container Variables
variable "management_container_id" {
  description = "Management container ID"
  type        = number
  default     = 100
}

variable "management_container_name" {
  description = "Management container hostname"
  type        = string
  default     = "infrastructure-mgmt"
}

variable "management_container_memory" {
  description = "Management container memory in MB"
  type        = number
  default     = 4096
}

variable "management_container_cores" {
  description = "Management container CPU cores"
  type        = number
  default     = 2
}

variable "management_container_storage" {
  description = "Management container storage size"
  type        = string
  default     = "20G"
}

variable "management_container_ip" {
  description = "Management container IP address"
  type        = string
  default     = "10.100.1.10/24"
}

variable "template_storage" {
  description = "Storage for container templates"
  type        = string
  default     = "local"
}

# Infrastructure VM Variables
variable "infrastructure_vm_configs" {
  description = "Configuration for infrastructure VMs"
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
  default = {
    "docker-host-01" = {
      vmid       = 201
      name       = "docker-host-01"
      desc       = "Docker container host"
      memory     = 8192
      cores      = 4
      sockets    = 1
      disk_size  = "50G"
      disk_type  = "scsi0"
      network_ip = "10.100.2.101/24"
      tags       = ["docker", "infrastructure"]
    }
    "k8s-master-01" = {
      vmid       = 211
      name       = "k8s-master-01"
      desc       = "Kubernetes master node"
      memory     = 4096
      cores      = 2
      sockets    = 1
      disk_size  = "40G"
      disk_type  = "scsi0"
      network_ip = "10.100.2.111/24"
      tags       = ["kubernetes", "master"]
    }
    "k8s-worker-01" = {
      vmid       = 221
      name       = "k8s-worker-01"
      desc       = "Kubernetes worker node"
      memory     = 8192
      cores      = 4
      sockets    = 1
      disk_size  = "60G"
      disk_type  = "scsi0"
      network_ip = "10.100.2.121/24"
      tags       = ["kubernetes", "worker"]
    }
  }
}

variable "vm_template_name" {
  description = "VM template name for cloning"
  type        = string
  default     = "ubuntu-22-04-template"
}

# Node Configuration
variable "target_node" {
  description = "Proxmox node name for resource deployment"
  type        = string
  default     = "pve"
}

# Cloud-init Configuration
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
  description = "SSH public keys for cloud-init"
  type        = list(string)
  default     = []
}

# Environment Variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "proxmox-infra"
}