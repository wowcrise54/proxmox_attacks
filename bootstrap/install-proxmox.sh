#!/bin/bash

# Proxmox Infrastructure Automation Bootstrap Script
# This script initializes a fresh Proxmox VE installation with infrastructure automation capabilities

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROXMOX_VERSION="8.0"
SDN_ZONE_NAME="infrastructure-zone"
MANAGEMENT_VNET="management-net"
INFRASTRUCTURE_VNET="infrastructure-net"
SERVICES_VNET="services-net"
MANAGEMENT_CONTAINER_ID="100"
MANAGEMENT_CONTAINER_NAME="infrastructure-mgmt"

# Network configuration
MANAGEMENT_SUBNET="10.100.1.0/24"
INFRASTRUCTURE_SUBNET="10.100.2.0/24"
SERVICES_SUBNET="10.100.3.0/24"
DHCP_RANGE_START_MGMT="10.100.1.100"
DHCP_RANGE_END_MGMT="10.100.1.200"
DHCP_RANGE_START_INFRA="10.100.2.100"
DHCP_RANGE_END_INFRA="10.100.2.200"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_proxmox_installation() {
    log "Checking Proxmox VE installation..."
    
    if ! command -v pvesh >/dev/null 2>&1; then
        error "Proxmox VE is not installed or pvesh command not found"
    fi
    
    if ! systemctl is-active --quiet pve-cluster; then
        error "Proxmox cluster service is not running"
    fi
    
    local pve_version=$(pveversion | grep "pve-manager" | cut -d'/' -f2 | cut -d'-' -f1)
    info "Proxmox VE version: $pve_version"
}

setup_repositories() {
    log "Setting up Proxmox repositories..."
    
    # Add non-subscription repository if not present
    if ! grep -q "pve-no-subscription" /etc/apt/sources.list.d/pve-install-repo.list 2>/dev/null; then
        echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >> /etc/apt/sources.list.d/pve-no-subscription.list
    fi
    
    # Update package lists
    apt-get update
    apt-get install -y curl wget gnupg2 software-properties-common
}

install_prerequisites() {
    log "Installing prerequisites..."
    
    apt-get install -y \
        bridge-utils \
        ifupdown2 \
        frr \
        frr-pythontools \
        dnsmasq \
        iptables-persistent \
        git \
        python3 \
        python3-pip \
        jq \
        unzip \
        libpve-network-perl
}

configure_sdn() {
    log "Configuring Software Defined Networking (SDN)..."
    
    # Check if SDN is already enabled
    if pvesh get /cluster/sdn/status >/dev/null 2>&1; then
        info "SDN is already configured"
    else
        info "Enabling SDN..."
        # Enable SDN if not already enabled
        pvesh set /cluster/sdn --enable 1
        
        # Wait a moment for SDN to initialize
        sleep 3
    fi
    
    # Create SDN Zone
    if ! pvesh get /cluster/sdn/zones/$SDN_ZONE_NAME >/dev/null 2>&1; then
        info "Creating SDN Zone: $SDN_ZONE_NAME"
        pvesh create /cluster/sdn/zones \
            --zoneid "$SDN_ZONE_NAME" \
            --type simple \
            --bridge vmbr1
    else
        info "SDN Zone $SDN_ZONE_NAME already exists"
    fi
    
    # Create Management VNET
    if ! pvesh get /cluster/sdn/vnets/$MANAGEMENT_VNET >/dev/null 2>&1; then
        info "Creating Management VNET: $MANAGEMENT_VNET"
        pvesh create /cluster/sdn/vnets \
            --vnet "$MANAGEMENT_VNET" \
            --zone "$SDN_ZONE_NAME" \
            --tag 100
    fi
    
    # Create Infrastructure VNET
    if ! pvesh get /cluster/sdn/vnets/$INFRASTRUCTURE_VNET >/dev/null 2>&1; then
        info "Creating Infrastructure VNET: $INFRASTRUCTURE_VNET"
        pvesh create /cluster/sdn/vnets \
            --vnet "$INFRASTRUCTURE_VNET" \
            --zone "$SDN_ZONE_NAME" \
            --tag 200
    fi
    
    # Create Services VNET
    if ! pvesh get /cluster/sdn/vnets/$SERVICES_VNET >/dev/null 2>&1; then
        info "Creating Services VNET: $SERVICES_VNET"
        pvesh create /cluster/sdn/vnets \
            --vnet "$SERVICES_VNET" \
            --zone "$SDN_ZONE_NAME" \
            --tag 300
    fi
}

configure_subnets() {
    log "Configuring SDN Subnets..."
    
    # Management subnet
    if ! pvesh get /cluster/sdn/vnets/$MANAGEMENT_VNET/subnets/$MANAGEMENT_SUBNET >/dev/null 2>&1; then
        info "Creating Management subnet: $MANAGEMENT_SUBNET"
        pvesh create /cluster/sdn/vnets/$MANAGEMENT_VNET/subnets \
            --subnet "$MANAGEMENT_SUBNET" \
            --gateway "10.100.1.1" \
            --snat 1 \
            --dhcp-range "start-address=$DHCP_RANGE_START_MGMT,end-address=$DHCP_RANGE_END_MGMT"
    fi
    
    # Infrastructure subnet
    if ! pvesh get /cluster/sdn/vnets/$INFRASTRUCTURE_VNET/subnets/$INFRASTRUCTURE_SUBNET >/dev/null 2>&1; then
        info "Creating Infrastructure subnet: $INFRASTRUCTURE_SUBNET"
        pvesh create /cluster/sdn/vnets/$INFRASTRUCTURE_VNET/subnets \
            --subnet "$INFRASTRUCTURE_SUBNET" \
            --gateway "10.100.2.1" \
            --snat 1 \
            --dhcp-range "start-address=$DHCP_RANGE_START_INFRA,end-address=$DHCP_RANGE_END_INFRA"
    fi
    
    # Services subnet
    if ! pvesh get /cluster/sdn/vnets/$SERVICES_VNET/subnets/$SERVICES_SUBNET >/dev/null 2>&1; then
        info "Creating Services subnet: $SERVICES_SUBNET"
        pvesh create /cluster/sdn/vnets/$SERVICES_VNET/subnets \
            --subnet "$SERVICES_SUBNET" \
            --gateway "10.100.3.1" \
            --snat 1 \
            --dhcp-range "start-address=10.100.3.100,end-address=10.100.3.200"
    fi
}

apply_sdn_configuration() {
    log "Applying SDN configuration..."
    pvesh set /cluster/sdn --apply 1
    sleep 5
    systemctl reload-or-restart frr
    systemctl reload-or-restart dnsmasq
}

create_management_container() {
    log "Creating management container..."
    
    # Check if container already exists
    if pct list | grep -q "$MANAGEMENT_CONTAINER_ID"; then
        warning "Container $MANAGEMENT_CONTAINER_ID already exists. Skipping creation."
        return
    fi
    
    # Download Ubuntu 22.04 template if not exists
    local template_storage="local"
    local template_file="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    
    if ! pvesm list $template_storage | grep -q "$template_file"; then
        info "Downloading Ubuntu 22.04 container template..."
        pveam download $template_storage $template_file
    fi
    
    # Create container
    info "Creating container $MANAGEMENT_CONTAINER_NAME (ID: $MANAGEMENT_CONTAINER_ID)"
    pct create $MANAGEMENT_CONTAINER_ID \
        $template_storage:vztmpl/$template_file \
        --hostname "$MANAGEMENT_CONTAINER_NAME" \
        --memory 4096 \
        --cores 2 \
        --rootfs local-lvm:20 \
        --net0 name=eth0,bridge=$MANAGEMENT_VNET,firewall=1,ip=dhcp \
        --unprivileged 1 \
        --start 1 \
        --onboot 1
    
    # Wait for container to start
    sleep 10
    
    # Configure container
    info "Configuring management container..."
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        apt-get update && apt-get upgrade -y
        apt-get install -y curl wget git python3 python3-pip unzip software-properties-common
        pip3 install --upgrade pip
    "
}

install_automation_tools_in_container() {
    log "Installing automation tools in management container..."
    
    # Install Terraform
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bookworm main' | tee /etc/apt/sources.list.d/hashicorp.list
        apt-get update
        apt-get install -y terraform
    "
    
    # Install Ansible
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        pip3 install ansible ansible-core
        ansible-galaxy collection install community.general
    "
    
    # Install Packer
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
        unzip packer_1.9.4_linux_amd64.zip
        mv packer /usr/local/bin/
        rm packer_1.9.4_linux_amd64.zip
    "
    
    # Install Proxmox API clients
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        pip3 install proxmoxer requests
    "
}

setup_container_workspace() {
    log "Setting up workspace in management container..."
    
    pct exec $MANAGEMENT_CONTAINER_ID -- bash -c "
        mkdir -p /opt/infrastructure/{terraform,ansible,packer,scripts}
        cd /opt/infrastructure
        git init
        echo 'Infrastructure automation workspace initialized' > README.md
    "
}

configure_firewall() {
    log "Configuring firewall rules..."
    
    # Enable IP forwarding
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    sysctl -p
    
    # Configure iptables for SNAT
    iptables -t nat -A POSTROUTING -s 10.100.0.0/16 -o vmbr0 -j MASQUERADE
    iptables-save > /etc/iptables/rules.v4
}

validate_installation() {
    log "Validating installation..."
    
    # Check SDN configuration
    if pvesh get /cluster/sdn/status | grep -q "ok"; then
        info "✓ SDN configuration is valid"
    else
        error "SDN configuration validation failed"
    fi
    
    # Check container status
    if pct status $MANAGEMENT_CONTAINER_ID | grep -q "running"; then
        info "✓ Management container is running"
    else
        error "Management container is not running"
    fi
    
    # Check container connectivity
    if pct exec $MANAGEMENT_CONTAINER_ID -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        info "✓ Management container has internet connectivity"
    else
        warning "Management container internet connectivity test failed"
    fi
    
    # Check tools installation
    if pct exec $MANAGEMENT_CONTAINER_ID -- terraform version >/dev/null 2>&1; then
        info "✓ Terraform is installed"
    else
        warning "Terraform installation check failed"
    fi
    
    if pct exec $MANAGEMENT_CONTAINER_ID -- ansible --version >/dev/null 2>&1; then
        info "✓ Ansible is installed"
    else
        warning "Ansible installation check failed"
    fi
    
    if pct exec $MANAGEMENT_CONTAINER_ID -- packer version >/dev/null 2>&1; then
        info "✓ Packer is installed"
    else
        warning "Packer installation check failed"
    fi
}

print_summary() {
    log "Installation completed successfully!"
    echo
    echo -e "${GREEN}=== Proxmox Infrastructure Automation Setup Summary ===${NC}"
    echo -e "Management Container ID: ${BLUE}$MANAGEMENT_CONTAINER_ID${NC}"
    echo -e "Management Container Name: ${BLUE}$MANAGEMENT_CONTAINER_NAME${NC}"
    echo -e "SDN Zone: ${BLUE}$SDN_ZONE_NAME${NC}"
    echo -e "Management Network: ${BLUE}$MANAGEMENT_VNET ($MANAGEMENT_SUBNET)${NC}"
    echo -e "Infrastructure Network: ${BLUE}$INFRASTRUCTURE_VNET ($INFRASTRUCTURE_SUBNET)${NC}"
    echo -e "Services Network: ${BLUE}$SERVICES_VNET ($SERVICES_SUBNET)${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Access the management container: pct enter $MANAGEMENT_CONTAINER_ID"
    echo "2. Navigate to workspace: cd /opt/infrastructure"
    echo "3. Deploy infrastructure using the provided scripts"
    echo
}

main() {
    log "Starting Proxmox Infrastructure Automation Bootstrap"
    
    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    check_proxmox_installation
    setup_repositories
    install_prerequisites
    configure_sdn
    configure_subnets
    apply_sdn_configuration
    create_management_container
    install_automation_tools_in_container
    setup_container_workspace
    configure_firewall
    validate_installation
    print_summary
    
    log "Bootstrap completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"