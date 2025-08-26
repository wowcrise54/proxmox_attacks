terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
  pm_parallel         = 1
  pm_timeout          = 600
}

# Data sources for existing resources
data "proxmox_version" "version" {}

# SDN Configuration Module
module "sdn" {
  source = "./modules/sdn"
  
  zone_name           = var.sdn_zone_name
  management_vnet     = var.management_vnet
  infrastructure_vnet = var.infrastructure_vnet
  services_vnet       = var.services_vnet
  
  management_subnet     = var.management_subnet
  infrastructure_subnet = var.infrastructure_subnet
  services_subnet       = var.services_subnet
  
  dhcp_ranges = var.dhcp_ranges
}

# Management Container Module
module "management_container" {
  source = "./modules/containers"
  
  depends_on = [module.sdn]
  
  container_id       = var.management_container_id
  container_name     = var.management_container_name
  container_memory   = var.management_container_memory
  container_cores    = var.management_container_cores
  container_storage  = var.management_container_storage
  
  network_bridge = var.management_vnet
  network_ip     = var.management_container_ip
  
  template_storage = var.template_storage
}

# Infrastructure VMs Module
module "infrastructure_vms" {
  source = "./modules/vms"
  
  depends_on = [module.sdn, module.management_container]
  
  vm_configs = var.infrastructure_vm_configs
  
  network_bridge = var.infrastructure_vnet
  template_name  = var.vm_template_name
  
  clone_wait    = 30
  agent         = 1
  boot          = "order=scsi0;ide2;net0"
  scsihw        = "virtio-scsi-pci"
}