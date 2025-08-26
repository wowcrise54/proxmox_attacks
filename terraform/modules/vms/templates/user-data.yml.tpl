#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

users:
  - name: ${username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    home: /home/${username}
    shell: /bin/bash
    lock_passwd: false
    passwd: ${password}
%{ if length(ssh_keys) > 0 ~}
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}
%{ endif ~}

# Package management
package_update: true
package_upgrade: true

packages:
%{ for package in packages ~}
  - ${package}
%{ endfor ~}

# Additional packages for infrastructure
  - cloud-init
  - cloud-utils
  - cloud-guest-utils

# System configuration
timezone: UTC
locale: en_US.UTF-8

# Network configuration
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false

# SSH configuration
ssh_pwauth: true
disable_root: false

# Service management
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable ssh
  - systemctl start ssh
  - |
    # Configure automatic security updates
    echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades
  - |
    # Set proper hostname resolution
    echo "127.0.0.1 ${hostname}" >> /etc/hosts
  - |
    # Update system and clean package cache
    apt-get update
    apt-get autoremove -y
    apt-get autoclean

# Write additional files
write_files:
  - path: /etc/motd
    content: |
      Welcome to ${hostname}
      
      This system is managed by Proxmox Infrastructure Automation
      
      System Information:
      - OS: Ubuntu 22.04 LTS
      - Managed by: Terraform + Ansible
      - Infrastructure: Proxmox VE
      
      For support, contact your system administrator.
    permissions: '0644'
  
  - path: /etc/systemd/system/infrastructure-ready.service
    content: |
      [Unit]
      Description=Infrastructure Ready Marker
      After=network-online.target
      Wants=network-online.target
      
      [Service]
      Type=oneshot
      ExecStart=/bin/touch /var/lib/infrastructure-ready
      RemainAfterExit=yes
      
      [Install]
      WantedBy=multi-user.target
    permissions: '0644'

# Final commands
final_message: |
  Cloud-init finished successfully!
  System: ${hostname}
  User: ${username}
  
  The system is ready for infrastructure automation.

# Power state
power_state:
  mode: reboot
  delay: "+1"
  message: "Rebooting after cloud-init completion"