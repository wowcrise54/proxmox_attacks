# Containers Module Outputs

output "container_id" {
  description = "Container ID"
  value       = proxmox_lxc.management_container.vmid
}

output "container_name" {
  description = "Container hostname"
  value       = proxmox_lxc.management_container.hostname
}

output "container_ip" {
  description = "Container IP address"
  value       = var.network_ip
}

output "container_status" {
  description = "Container status"
  value       = proxmox_lxc.management_container.start ? "running" : "stopped"
}

output "container_node" {
  description = "Proxmox node hosting the container"
  value       = proxmox_lxc.management_container.target_node
}

output "container_access" {
  description = "Container access information"
  value = {
    ssh_command = "pct enter ${proxmox_lxc.management_container.vmid}"
    workspace   = "/opt/infrastructure"
    ip_address  = var.network_ip
  }
}

output "workspace_path" {
  description = "Path to workspace directory in container"
  value       = "/opt/infrastructure"
}