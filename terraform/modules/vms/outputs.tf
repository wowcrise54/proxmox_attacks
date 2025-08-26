# VMs Module Outputs

output "vms" {
  description = "Information about created VMs"
  value = {
    for k, vm in proxmox_vm_qemu.infrastructure_vms : k => {
      id                   = vm.vmid
      name                 = vm.name
      status               = "running"
      target_node          = vm.target_node
      default_ipv4_address = split("/", var.vm_configs[k].network_ip)[0]
      memory               = vm.memory
      cores                = vm.cores
      tags                 = var.vm_configs[k].tags
    }
  }
}

output "vm_list" {
  description = "Simple list of VM names and IDs"
  value = {
    for k, vm in proxmox_vm_qemu.infrastructure_vms : vm.name => vm.vmid
  }
}

output "vm_ips" {
  description = "VM IP addresses"
  value = {
    for k, vm in proxmox_vm_qemu.infrastructure_vms : vm.name => split("/", var.vm_configs[k].network_ip)[0]
  }
}

output "vm_ssh_info" {
  description = "SSH connection information for VMs"
  value = {
    for k, vm in proxmox_vm_qemu.infrastructure_vms : vm.name => {
      ip_address = split("/", var.vm_configs[k].network_ip)[0]
      ssh_user   = var.ci_user
      ssh_command = "ssh ${var.ci_user}@${split("/", var.vm_configs[k].network_ip)[0]}"
    }
  }
}

output "ansible_inventory" {
  description = "Ansible inventory format for created VMs"
  value = {
    for k, vm in proxmox_vm_qemu.infrastructure_vms : vm.name => {
      ansible_host = split("/", var.vm_configs[k].network_ip)[0]
      ansible_user = var.ci_user
      groups       = var.vm_configs[k].tags
    }
  }
}