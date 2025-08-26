# Production Environment Configuration
# This file contains production-ready configurations with enhanced security and performance

# Environment Configuration
environment = "prod"
project_name = "proxmox-infra-prod"

# Target Node
target_node = "pve"

# SDN Configuration
sdn_zone_name = "production-zone"
management_vnet = "mgmt-net-prod"
infrastructure_vnet = "infra-net-prod" 
services_vnet = "services-net-prod"

# Network Configuration (Different subnets for production)
management_subnet = "10.200.1.0/24"
infrastructure_subnet = "10.200.2.0/24"
services_subnet = "10.200.3.0/24"

dhcp_ranges = {
  management = {
    start = "10.200.1.50"
    end   = "10.200.1.100"
  }
  infrastructure = {
    start = "10.200.2.50"
    end   = "10.200.2.100"  
  }
  services = {
    start = "10.200.3.50"
    end   = "10.200.3.100"
  }
}

# Management Container Configuration (Enhanced for production)
management_container_id = 100
management_container_name = "infrastructure-mgmt-prod"
management_container_memory = 8192  # Increased for production
management_container_cores = 4      # Increased for production
management_container_storage = "40G" # Increased for production
management_container_ip = "10.200.1.10/24"

# Template Configuration
template_storage = "local"
vm_template_name = "ubuntu-22-04-template"

# Cloud-init Configuration
ci_user = "ubuntu"
# Use strong password or key-only authentication in production
ci_password = "SecureProductionPassword123!"

# SSH Keys (Required for production)
ssh_keys = [
  # Add your production SSH public keys here
  # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... admin@company.com"
  # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... deploy@company.com"
]

# Production Infrastructure VMs Configuration
infrastructure_vm_configs = {
  # Load Balancer
  "lb-01" = {
    vmid       = 301
    name       = "lb-01-prod"
    desc       = "Load Balancer - Production"
    memory     = 4096
    cores      = 2
    sockets    = 1
    disk_size  = "40G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.101/24"
    tags       = ["loadbalancer", "nginx", "production"]
  }
  
  "lb-02" = {
    vmid       = 302
    name       = "lb-02-prod"
    desc       = "Load Balancer - Production (HA)"
    memory     = 4096
    cores      = 2
    sockets    = 1
    disk_size  = "40G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.102/24"
    tags       = ["loadbalancer", "nginx", "production", "ha"]
  }
  
  # Docker Swarm Cluster
  "docker-mgr-01" = {
    vmid       = 311
    name       = "docker-mgr-01-prod"
    desc       = "Docker Swarm Manager - Production"
    memory     = 8192
    cores      = 4
    sockets    = 1
    disk_size  = "100G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.111/24"
    tags       = ["docker", "swarm", "manager", "production"]
  }
  
  "docker-mgr-02" = {
    vmid       = 312
    name       = "docker-mgr-02-prod"
    desc       = "Docker Swarm Manager - Production (HA)"
    memory     = 8192
    cores      = 4
    sockets    = 1
    disk_size  = "100G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.112/24"
    tags       = ["docker", "swarm", "manager", "production", "ha"]
  }
  
  "docker-worker-01" = {
    vmid       = 321
    name       = "docker-worker-01-prod"
    desc       = "Docker Swarm Worker - Production"
    memory     = 16384
    cores      = 6
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.121/24"
    tags       = ["docker", "swarm", "worker", "production"]
  }
  
  "docker-worker-02" = {
    vmid       = 322
    name       = "docker-worker-02-prod"
    desc       = "Docker Swarm Worker - Production"
    memory     = 16384
    cores      = 6
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.122/24"
    tags       = ["docker", "swarm", "worker", "production"]
  }
  
  # Kubernetes Cluster
  "k8s-master-01" = {
    vmid       = 331
    name       = "k8s-master-01-prod"
    desc       = "Kubernetes Master - Production"
    memory     = 8192
    cores      = 4
    sockets    = 1
    disk_size  = "100G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.131/24"
    tags       = ["kubernetes", "master", "production"]
  }
  
  "k8s-master-02" = {
    vmid       = 332
    name       = "k8s-master-02-prod"
    desc       = "Kubernetes Master - Production (HA)"
    memory     = 8192
    cores      = 4
    sockets    = 1
    disk_size  = "100G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.132/24"
    tags       = ["kubernetes", "master", "production", "ha"]
  }
  
  "k8s-worker-01" = {
    vmid       = 341
    name       = "k8s-worker-01-prod"
    desc       = "Kubernetes Worker - Production"
    memory     = 16384
    cores      = 8
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.141/24"
    tags       = ["kubernetes", "worker", "production"]
  }
  
  "k8s-worker-02" = {
    vmid       = 342
    name       = "k8s-worker-02-prod"
    desc       = "Kubernetes Worker - Production"
    memory     = 16384
    cores      = 8
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.142/24"
    tags       = ["kubernetes", "worker", "production"]
  }
  
  "k8s-worker-03" = {
    vmid       = 343
    name       = "k8s-worker-03-prod"
    desc       = "Kubernetes Worker - Production"
    memory     = 16384
    cores      = 8
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.143/24"
    tags       = ["kubernetes", "worker", "production"]
  }
  
  # Database Servers
  "db-master-01" = {
    vmid       = 351
    name       = "db-master-01-prod"
    desc       = "Database Master - Production"
    memory     = 32768
    cores      = 8
    sockets    = 1
    disk_size  = "500G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.151/24"
    tags       = ["database", "postgresql", "master", "production"]
  }
  
  "db-replica-01" = {
    vmid       = 352
    name       = "db-replica-01-prod"
    desc       = "Database Replica - Production"
    memory     = 16384
    cores      = 6
    sockets    = 1
    disk_size  = "500G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.152/24"
    tags       = ["database", "postgresql", "replica", "production"]
  }
  
  # Monitoring and Logging
  "monitor-01" = {
    vmid       = 361
    name       = "monitor-01-prod"
    desc       = "Monitoring Server - Production"
    memory     = 8192
    cores      = 4
    sockets    = 1
    disk_size  = "200G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.161/24"
    tags       = ["monitoring", "prometheus", "grafana", "production"]
  }
  
  # Backup Server
  "backup-01" = {
    vmid       = 371
    name       = "backup-01-prod"
    desc       = "Backup Server - Production"
    memory     = 4096
    cores      = 2
    sockets    = 1
    disk_size  = "1000G"
    disk_type  = "scsi0"
    network_ip = "10.200.2.171/24"
    tags       = ["backup", "restic", "production"]
  }
}