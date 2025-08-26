# Containers Module for Proxmox Infrastructure
# This module manages LXC containers

terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
    }
  }
}

# Data source for the latest Ubuntu 22.04 LXC template
data "proxmox_template_file" "ubuntu_template" {
  content_type = "vztmpl"
  datastore_id = var.template_storage
  node         = var.target_node
}

# Management Container Resource
resource "proxmox_lxc" "management_container" {
  target_node     = var.target_node
  hostname        = var.container_name
  vmid            = var.container_id
  password        = var.container_password
  unprivileged    = true
  
  # Container specifications
  memory          = var.container_memory
  cores           = var.container_cores
  
  # Root filesystem
  rootfs {
    storage = "local-lvm"
    size    = var.container_storage
  }
  
  # Network configuration
  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = var.network_ip
    gw     = cidrhost(var.network_ip, 1)
  }
  
  # Container features
  features {
    nesting = true
    mount   = "nfs;cifs"
  }
  
  # OS template
  ostemplate = "${var.template_storage}:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  
  # Start container on boot
  onboot = true
  start  = true
  
  # SSH key configuration
  ssh_public_keys = length(var.ssh_keys) > 0 ? join("\n", var.ssh_keys) : null
  
  # Lifecycle management
  lifecycle {
    ignore_changes = [
      # Ignore changes to template as it may be updated externally
      ostemplate,
    ]
  }
  
  # Tags for organization
  tags = join(";", var.container_tags)
}

# Wait for container to be fully started
resource "null_resource" "wait_for_container" {
  depends_on = [proxmox_lxc.management_container]
  
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Install automation tools in the container
resource "null_resource" "install_tools" {
  depends_on = [null_resource.wait_for_container]
  
  # Trigger reinstallation if tools list changes
  triggers = {
    container_id = var.container_id
    tools_hash   = md5(join(",", var.automation_tools))
  }
  
  # Install tools via Proxmox API
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for container to be ready
      sleep 10
      
      # Update package lists
      pct exec ${var.container_id} -- apt-get update
      
      # Install basic tools
      pct exec ${var.container_id} -- apt-get install -y curl wget git python3 python3-pip unzip software-properties-common
      
      # Install Terraform
      pct exec ${var.container_id} -- bash -c "
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bookworm main' | tee /etc/apt/sources.list.d/hashicorp.list
        apt-get update
        apt-get install -y terraform
      "
      
      # Install Ansible
      pct exec ${var.container_id} -- pip3 install ansible ansible-core
      
      # Install Packer
      pct exec ${var.container_id} -- bash -c "
        wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
        unzip packer_1.9.4_linux_amd64.zip
        mv packer /usr/local/bin/
        rm packer_1.9.4_linux_amd64.zip
      "
      
      # Install Proxmox API clients
      pct exec ${var.container_id} -- pip3 install proxmoxer requests
    EOT
  }
}

# Setup workspace in container
resource "null_resource" "setup_workspace" {
  depends_on = [null_resource.install_tools]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Create workspace directories
      pct exec ${var.container_id} -- mkdir -p /opt/infrastructure/{terraform,ansible,packer,scripts}
      
      # Initialize git repository
      pct exec ${var.container_id} -- bash -c "cd /opt/infrastructure && git init"
      
      # Create basic README
      pct exec ${var.container_id} -- bash -c "echo 'Infrastructure automation workspace' > /opt/infrastructure/README.md"
      
      # Set proper permissions
      pct exec ${var.container_id} -- chown -R root:root /opt/infrastructure
      pct exec ${var.container_id} -- chmod -R 755 /opt/infrastructure
    EOT
  }
}