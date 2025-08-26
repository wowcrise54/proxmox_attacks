packer {
  required_plugins {
    proxmox = {
      version = "~> 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# Variable definitions
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL"
  default     = "https://localhost:8006/api2/json"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API Token ID"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API Token Secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
  default     = "pve"
}

variable "proxmox_storage_pool" {
  type        = string
  description = "Proxmox storage pool"
  default     = "local-lvm"
}

variable "proxmox_storage_pool_type" {
  type        = string
  description = "Proxmox storage pool type"
  default     = "lvm-thin"
}

variable "iso_storage_pool" {
  type        = string
  description = "ISO storage pool"
  default     = "local"
}

variable "template_name" {
  type        = string
  description = "Template name"
  default     = "ubuntu-22-04-template"
}

variable "template_description" {
  type        = string
  description = "Template description"
  default     = "Ubuntu 22.04 LTS Base Template - Built with Packer"
}

# Local variables
locals {
  template_name = "${var.template_name}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}

# Source configuration
source "proxmox-iso" "ubuntu-22-04-base" {
  # Proxmox connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # VM configuration
  vm_name              = local.template_name
  vm_id                = 9999
  template_name        = var.template_name
  template_description = var.template_description

  # ISO configuration
  iso_file         = "local:iso/ubuntu-22.04.3-live-server-amd64.iso"
  iso_checksum     = "sha256:a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd"
  iso_storage_pool = var.iso_storage_pool
  unmount_iso      = true

  # Hardware configuration
  memory       = 2048
  cores        = 2
  sockets      = 1
  cpu_type     = "host"
  scsi_controller = "virtio-scsi-pci"

  # Disk configuration
  disks {
    type         = "scsi"
    disk_size    = "20G"
    storage_pool = var.proxmox_storage_pool
    format       = "qcow2"
  }

  # Network configuration
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Boot configuration
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]

  # HTTP server for autoinstall
  http_directory = "packer/http"
  http_bind_address = "0.0.0.0"
  http_port_min = 8080
  http_port_max = 8090

  # SSH configuration
  ssh_username = "ubuntu"
  ssh_password = "ubuntu"
  ssh_timeout = "30m"

  # Cloud-init
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool

  # Template conversion
  template = true
}

# Build configuration
build {
  name = "ubuntu-22-04-base"
  sources = [
    "source.proxmox-iso.ubuntu-22-04-base"
  ]

  # Wait for SSH connection
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to be ready...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done"
    ]
  }

  # System update
  provisioner "shell" {
    inline = [
      "echo 'Starting system update...'",
      "sudo apt-get update",
      "sudo apt-get upgrade -y",
      "sudo apt-get dist-upgrade -y"
    ]
  }

  # Install essential packages
  provisioner "shell" {
    inline = [
      "echo 'Installing essential packages...'",
      "sudo apt-get install -y",
      "  curl",
      "  wget", 
      "  git",
      "  vim",
      "  htop",
      "  net-tools",
      "  software-properties-common",
      "  apt-transport-https",
      "  ca-certificates",
      "  gnupg",
      "  lsb-release",
      "  cloud-init",
      "  cloud-utils",
      "  cloud-guest-utils",
      "  qemu-guest-agent"
    ]
  }

  # Configure QEMU Guest Agent
  provisioner "shell" {
    inline = [
      "echo 'Configuring QEMU Guest Agent...'",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent"
    ]
  }

  # Configure cloud-init
  provisioner "shell" {
    inline = [
      "echo 'Configuring cloud-init...'",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id"
    ]
  }

  # Network configuration cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up network configuration...'",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg"
    ]
  }

  # SSH key cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up SSH configuration...'",
      "sudo rm -f /home/ubuntu/.ssh/authorized_keys",
      "sudo rm -f /root/.ssh/authorized_keys"
    ]
  }

  # System cleanup
  provisioner "shell" {
    inline = [
      "echo 'Performing final system cleanup...'",
      "sudo apt-get autoremove -y",
      "sudo apt-get autoclean",
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /var/log/wtmp",
      "sudo truncate -s 0 /var/log/lastlog",
      "sudo rm -f /var/log/cloud-init*.log",
      "sudo rm -f /var/log/auth.log*",
      "sudo rm -f /var/log/syslog*",
      "history -c && history -w"
    ]
  }

  # Final message
  provisioner "shell" {
    inline = [
      "echo 'Template build completed successfully!'",
      "echo 'Template: ${var.template_name}'",
      "echo 'Build time: $(date)'"
    ]
  }
}