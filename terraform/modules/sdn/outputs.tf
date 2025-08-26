# SDN Module Outputs

output "zone_status" {
  description = "Status of the SDN zone"
  value       = data.external.sdn_status.result
}

output "zone_name" {
  description = "Name of the created SDN zone"
  value       = var.zone_name
}

output "vnets" {
  description = "Created VNETs"
  value       = local.vnets
}

output "subnets" {
  description = "Subnet configuration"
  value       = local.subnets
}

output "network_config" {
  description = "Complete network configuration"
  value       = local.network_config
}

output "dhcp_ranges" {
  description = "DHCP ranges configuration"
  value       = var.dhcp_ranges
}