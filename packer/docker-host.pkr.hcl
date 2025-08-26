packer {
  required_plugins {
    proxmox = {
      version = "~> 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# Variable definitions (inherit from base template)
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

variable "base_template_name" {
  type        = string
  description = "Base template to clone from"
  default     = "ubuntu-22-04-template"
}

variable "template_name" {
  type        = string
  description = "Docker host template name"
  default     = "docker-host-template"
}

variable "docker_version" {
  type        = string
  description = "Docker version to install"
  default     = "24.0.*"
}

# Local variables
locals {
  template_name = "${var.template_name}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}

# Source configuration - Clone from base template
source "proxmox-clone" "docker-host" {
  # Proxmox connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # Clone configuration
  clone_vm                 = var.base_template_name
  vm_name                  = local.template_name
  vm_id                    = 9998
  template_name            = var.template_name
  template_description     = "Docker Host Template - Ubuntu 22.04 with Docker and Docker Compose"

  # Hardware adjustments for Docker workloads
  memory       = 4096
  cores        = 2
  sockets      = 1

  # Network configuration
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # SSH configuration
  ssh_username = "ubuntu"
  ssh_password = "ubuntu"
  ssh_timeout = "30m"

  # Cloud-init
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  # Template conversion
  template = true
}

# Build configuration
build {
  name = "docker-host-template"
  sources = [
    "source.proxmox-clone.docker-host"
  ]

  # Wait for system to be ready
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to be ready...'",
      "sudo cloud-init status --wait",
      "sleep 10"
    ]
  }

  # System update
  provisioner "shell" {
    inline = [
      "echo 'Updating system packages...'",
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }

  # Install Docker dependencies
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker dependencies...'",
      "sudo apt-get install -y",
      "  apt-transport-https",
      "  ca-certificates", 
      "  curl",
      "  gnupg",
      "  lsb-release",
      "  software-properties-common"
    ]
  }

  # Add Docker repository
  provisioner "shell" {
    inline = [
      "echo 'Adding Docker repository...'",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update"
    ]
  }

  # Install Docker Engine
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker Engine...'",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }

  # Configure Docker
  provisioner "shell" {
    inline = [
      "echo 'Configuring Docker...'",
      "sudo usermod -aG docker ubuntu",
      "sudo mkdir -p /etc/docker"
    ]
  }

  # Create Docker daemon configuration
  provisioner "file" {
    content = jsonencode({
      log-driver = "json-file"
      log-opts = {
        max-size = "10m"
        max-file = "3"
      }
      storage-driver = "overlay2"
    })
    destination = "/tmp/daemon.json"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/daemon.json /etc/docker/daemon.json",
      "sudo systemctl restart docker"
    ]
  }

  # Install Docker Compose standalone (for compatibility)
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker Compose standalone...'",
      "sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose"
    ]
  }

  # Install additional container tools
  provisioner "shell" {
    inline = [
      "echo 'Installing additional container tools...'",
      "sudo apt-get install -y",
      "  jq",
      "  yq", 
      "  tree",
      "  rsync",
      "  unzip"
    ]
  }

  # Configure system for containers
  provisioner "shell" {
    inline = [
      "echo 'Configuring system for containers...'",
      "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf",
      "echo 'fs.file-max=65536' | sudo tee -a /etc/sysctl.conf"
    ]
  }

  # Create useful directories and scripts
  provisioner "shell" {
    inline = [
      "echo 'Setting up container workspace...'",
      "mkdir -p /home/ubuntu/{containers,docker-compose,scripts}",
      "chown -R ubuntu:ubuntu /home/ubuntu/{containers,docker-compose,scripts}"
    ]
  }

  # Create Docker management script
  provisioner "file" {
    content = <<-EOF
#!/bin/bash
# Docker management script

case "$1" in
  status)
    echo "Docker Status:"
    sudo systemctl status docker --no-pager
    echo -e "\nDocker Version:"
    docker --version
    docker compose version
    echo -e "\nRunning Containers:"
    docker ps
    ;;
  logs)
    echo "Recent Docker logs:"
    sudo journalctl -u docker --no-pager -n 50
    ;;
  cleanup)
    echo "Cleaning up Docker resources..."
    docker system prune -f
    docker volume prune -f
    docker network prune -f
    echo "Cleanup completed."
    ;;
  *)
    echo "Usage: $0 {status|logs|cleanup}"
    exit 1
    ;;
esac
EOF
    destination = "/tmp/docker-mgmt.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/docker-mgmt.sh /usr/local/bin/docker-mgmt",
      "sudo chmod +x /usr/local/bin/docker-mgmt"
    ]
  }

  # Test Docker installation
  provisioner "shell" {
    inline = [
      "echo 'Testing Docker installation...'",
      "sudo docker run --rm hello-world",
      "docker --version",
      "docker compose version"
    ]
  }

  # System cleanup
  provisioner "shell" {
    inline = [
      "echo 'Performing system cleanup...'",
      "sudo apt-get autoremove -y",
      "sudo apt-get autoclean",
      "sudo docker system prune -f",
      "sudo cloud-init clean --logs"
    ]
  }

  # Final configuration
  provisioner "shell" {
    inline = [
      "echo 'Finalizing Docker host template...'",
      "echo 'Docker Host Template Build' | sudo tee /etc/motd",
      "echo 'Template build completed at: $(date)' | sudo tee -a /etc/motd",
      "echo 'Docker version: $(docker --version)' | sudo tee -a /etc/motd"
    ]
  }
}