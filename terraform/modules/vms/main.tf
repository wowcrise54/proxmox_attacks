# VMs Module for Proxmox Infrastructure
# This module manages virtual machines cloned from templates

terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
    }
  }
}

# Create VMs from template
resource "proxmox_vm_qemu" "infrastructure_vms" {
  for_each = var.vm_configs
  
  # Basic VM configuration
  name         = each.value.name
  vmid         = each.value.vmid
  target_node  = var.target_node
  desc         = each.value.desc
  
  # Clone from template
  clone    = var.template_name
  os_type  = "cloud-init"
  qemu_os  = "l26"
  
  # Hardware configuration
  memory   = each.value.memory
  cores    = each.value.cores
  sockets  = each.value.sockets
  cpu      = "host"
  
  # Boot configuration
  boot     = var.boot
  scsihw   = var.scsihw
  bootdisk = each.value.disk_type
  agent    = var.agent
  
  # Disk configuration
  disk {
    slot    = 0
    type    = "scsi"
    storage = var.disk_storage
    size    = each.value.disk_size
    format  = "qcow2"
    ssd     = 1
    discard = "on"
  }
  
  # Network configuration
  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
  
  # Cloud-init configuration
  cicustom = "user=local:snippets/user-data-${each.value.name}.yml"
  ipconfig0 = "ip=${each.value.network_ip},gw=${cidrhost(each.value.network_ip, 1)}"
  
  # SSH configuration
  sshkeys = length(var.ssh_keys) > 0 ? join("\n", var.ssh_keys) : null
  
  # Tags for organization
  tags = join(";", each.value.tags)
  
  # VM lifecycle
  onboot = true
  
  # Wait for clone to complete
  clone_wait = var.clone_wait
  
  # Prevent changes to template
  lifecycle {
    ignore_changes = [
      clone,
      disk,
    ]
  }
}

# Wait for VMs to be ready
resource "null_resource" "wait_for_vms" {
  for_each = var.vm_configs
  
  depends_on = [proxmox_vm_qemu.infrastructure_vms]
  
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Create cloud-init user-data files for each VM
resource "local_file" "cloud_init_user_data" {
  for_each = var.vm_configs
  
  filename = "/tmp/user-data-${each.value.name}.yml"
  
  content = templatefile("${path.module}/templates/user-data.yml.tpl", {
    hostname = each.value.name
    username = var.ci_user
    password = var.ci_password
    ssh_keys = var.ssh_keys
    packages = var.default_packages
  })
  
  # Upload to Proxmox snippets storage
  provisioner "local-exec" {
    command = <<-EOT
      # Copy user-data to Proxmox snippets directory
      scp /tmp/user-data-${each.value.name}.yml root@${var.proxmox_host}:/var/lib/vz/snippets/user-data-${each.value.name}.yml
    EOT
  }
}

# Health check for VMs
resource "null_resource" "vm_health_check" {
  for_each = var.vm_configs
  
  depends_on = [null_resource.wait_for_vms]
  
  # Trigger health check if VM IP changes
  triggers = {
    vm_ip = each.value.network_ip
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for VM to be accessible
      timeout 300 bash -c 'until ping -c 1 ${split("/", each.value.network_ip)[0]}; do sleep 5; done'
      echo "VM ${each.value.name} is accessible"
    EOT
  }
}