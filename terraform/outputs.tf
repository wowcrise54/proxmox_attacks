# SDN Outputs
output "sdn_zone_status" {
  description = "Status of the SDN zone"
  value       = module.sdn.zone_status
}

output "vnets_created" {
  description = "List of created VNETs"
  value       = module.sdn.vnets
}

output "subnets_created" {
  description = "Configuration of created subnets"
  value       = module.sdn.subnets
}

# Management Container Outputs
output "management_container_id" {
  description = "Management container ID"
  value       = module.management_container.container_id
}

output "management_container_ip" {
  description = "Management container IP address"
  value       = module.management_container.container_ip
}

output "management_container_status" {
  description = "Management container status"
  value       = module.management_container.container_status
}

# Infrastructure VMs Outputs
output "infrastructure_vms" {
  description = "Infrastructure VMs information"
  value = {
    for k, v in module.infrastructure_vms.vms : k => {
      id     = v.id
      name   = v.name
      ip     = v.default_ipv4_address
      status = v.status
      node   = v.target_node
    }
  }
}

output "vm_ssh_access" {
  description = "SSH access information for VMs"
  value = {
    for k, v in module.infrastructure_vms.vms : k => {
      ssh_command = "ssh ${var.ci_user}@${v.default_ipv4_address}"
      vm_id       = v.id
    }
  }
  sensitive = false
}

# Network Information
output "network_summary" {
  description = "Summary of network configuration"
  value = {
    management_network = {
      vnet   = var.management_vnet
      subnet = var.management_subnet
      dhcp   = var.dhcp_ranges.management
    }
    infrastructure_network = {
      vnet   = var.infrastructure_vnet
      subnet = var.infrastructure_subnet
      dhcp   = var.dhcp_ranges.infrastructure
    }
    services_network = {
      vnet   = var.services_vnet
      subnet = var.services_subnet
      dhcp   = var.dhcp_ranges.services
    }
  }
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    environment          = var.environment
    project_name        = var.project_name
    proxmox_node        = var.target_node
    management_container = "${var.management_container_name} (ID: ${var.management_container_id})"
    vm_count            = length(var.infrastructure_vm_configs)
    deployment_time     = timestamp()
  }
}

# Connection Information
output "proxmox_connection" {
  description = "Proxmox connection information"
  value = {
    api_url = var.proxmox_api_url
    node    = var.target_node
  }
  sensitive = false
}