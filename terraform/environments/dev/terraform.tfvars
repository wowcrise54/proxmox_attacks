# Development Environment Configuration

# Proxmox Connection (set via environment variables)
# PROXMOX_API_URL="https://your-proxmox-host:8006/api2/json"
# PROXMOX_API_TOKEN_ID="your-token-id"
# PROXMOX_API_TOKEN_SECRET="your-token-secret"

proxmox_tls_insecure = true

# Environment Configuration
environment = "dev"
project_name = "proxmox-infra-dev"

# Target Node
target_node = "pve"

# SDN Configuration
sdn_zone_name = "infrastructure-zone"
management_vnet = "management-net"
infrastructure_vnet = "infrastructure-net"
services_vnet = "services-net"

# Network Configuration
management_subnet = "10.100.1.0/24"
infrastructure_subnet = "10.100.2.0/24"
services_subnet = "10.100.3.0/24"

dhcp_ranges = {
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

# Management Container Configuration
management_container_id = 100
management_container_name = "infrastructure-mgmt-dev"
management_container_memory = 4096
management_container_cores = 2
management_container_storage = "20G"
management_container_ip = "10.100.1.10/24"

# Template Configuration
template_storage = "local"
vm_template_name = "ubuntu-22-04-template"

# Cloud-init Configuration
ci_user = "ubuntu"
ci_password = "ubuntu123"

# SSH Keys (add your public keys here)
ssh_keys = [
  # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-key-here"
]

# Infrastructure VMs Configuration
infrastructure_vm_configs = {
  "docker-host-01" = {
    vmid       = 201
    name       = "docker-host-01-dev"
    desc       = "Docker container host - Development"
    memory     = 4096
    cores      = 2
    sockets    = 1
    disk_size  = "40G"
    disk_type  = "scsi0"
    network_ip = "10.100.2.101/24"
    tags       = ["docker", "development", "infrastructure"]
  }
  
  "k8s-master-01" = {
    vmid       = 211
    name       = "k8s-master-01-dev"
    desc       = "Kubernetes master node - Development"
    memory     = 2048
    cores      = 2
    sockets    = 1
    disk_size  = "30G"
    disk_type  = "scsi0"
    network_ip = "10.100.2.111/24"
    tags       = ["kubernetes", "master", "development"]
  }
  
  "k8s-worker-01" = {
    vmid       = 221
    name       = "k8s-worker-01-dev"
    desc       = "Kubernetes worker node - Development"
    memory     = 4096
    cores      = 2
    sockets    = 1
    disk_size  = "40G"
    disk_type  = "scsi0"
    network_ip = "10.100.2.121/24"
    tags       = ["kubernetes", "worker", "development"]
  }
}