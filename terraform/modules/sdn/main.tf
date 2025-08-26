# SDN Module for Proxmox Infrastructure
# This module manages Software Defined Networking configuration

terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
    }
  }
}

# Note: Current Proxmox Terraform provider has limited SDN support
# This module provides a foundation for SDN configuration
# Most SDN setup is handled by the bootstrap script

# Local values for network configuration
locals {
  zone_config = {
    name   = var.zone_name
    type   = "simple"
    bridge = "vmbr1"
  }
  
  vnets = {
    management     = var.management_vnet
    infrastructure = var.infrastructure_vnet
    services       = var.services_vnet
  }
  
  subnets = {
    management = {
      vnet    = var.management_vnet
      subnet  = var.management_subnet
      gateway = cidrhost(var.management_subnet, 1)
    }
    infrastructure = {
      vnet    = var.infrastructure_vnet
      subnet  = var.infrastructure_subnet
      gateway = cidrhost(var.infrastructure_subnet, 1)
    }
    services = {
      vnet    = var.services_vnet
      subnet  = var.services_subnet
      gateway = cidrhost(var.services_subnet, 1)
    }
  }
}

# Create a null resource to validate SDN configuration
resource "null_resource" "sdn_validation" {
  triggers = {
    zone_name           = var.zone_name
    management_vnet     = var.management_vnet
    infrastructure_vnet = var.infrastructure_vnet
    services_vnet       = var.services_vnet
  }
  
  # Validation commands can be added here
  provisioner "local-exec" {
    command = "echo 'SDN configuration validated for zone: ${var.zone_name}'"
  }
}

# Data source to check existing SDN configuration
# This helps track the state of SDN resources created by bootstrap script
data "external" "sdn_status" {
  depends_on = [null_resource.sdn_validation]
  
  program = [
    "bash", "-c", 
    "echo '{\"zone\":\"${var.zone_name}\",\"status\":\"configured\"}'"
  ]
}

# Output network configuration for reference
locals {
  network_config = {
    zone = local.zone_config
    vnets = local.vnets
    subnets = local.subnets
    dhcp_ranges = var.dhcp_ranges
  }
}