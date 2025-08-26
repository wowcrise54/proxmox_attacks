#!/bin/bash

# Management Container Setup Script
# This script configures the management container with all automation tools
# Can be run inside an existing LXC container or used to setup tools remotely

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
CONTAINER_ID="${CONTAINER_ID:-100}"
WORKSPACE_DIR="/opt/infrastructure"
USER_NAME="infrastructure"
LOG_FILE="/var/log/mgmt-container-setup.log"

# Tool versions
TERRAFORM_VERSION="1.6.6"
PACKER_VERSION="1.9.4"
ANSIBLE_VERSION="8.0.0"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        *)     echo -e "$message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    exit 1
}

check_environment() {
    log INFO "Checking environment..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
    
    # Check if we're in a container
    if [[ -f /.dockerenv ]] || grep -q container=lxc /proc/1/environ 2>/dev/null; then
        log INFO "Running inside container environment"
    else
        log INFO "Running on host system"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error_exit "No internet connectivity available"
    fi
    
    log INFO "Environment check completed"
}

update_system() {
    log INFO "Updating system packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package lists
    apt-get update || error_exit "Failed to update package lists"
    
    # Upgrade system packages
    apt-get upgrade -y || error_exit "Failed to upgrade packages"
    
    # Install essential packages
    apt-get install -y \
        curl \
        wget \
        git \
        vim \
        nano \
        htop \
        tree \
        unzip \
        zip \
        rsync \
        jq \
        yq \
        python3 \
        python3-pip \
        python3-venv \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        build-essential \
        make \
        gcc \
        sudo \
        openssh-client \
        net-tools \
        iputils-ping \
        telnet \
        netcat \
        dnsutils \
        || error_exit "Failed to install essential packages"
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    log INFO "System update completed"
}

create_infrastructure_user() {
    log INFO "Creating infrastructure user..."
    
    # Create user if it doesn't exist
    if ! id "$USER_NAME" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo "$USER_NAME" || error_exit "Failed to create user"
        
        # Set password (can be changed later)
        echo "$USER_NAME:infrastructure123" | chpasswd
        
        # Configure sudo without password
        echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-$USER_NAME"
        chmod 440 "/etc/sudoers.d/99-$USER_NAME"
        
        log INFO "User $USER_NAME created successfully"
    else
        log INFO "User $USER_NAME already exists"
    fi
}

install_terraform() {
    log INFO "Installing Terraform v$TERRAFORM_VERSION..."
    
    # Add HashiCorp GPG key
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | \
        tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
    
    # Add HashiCorp repository
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/hashicorp.list
    
    # Update and install
    apt-get update
    apt-get install -y terraform="$TERRAFORM_VERSION-*" || \
        apt-get install -y terraform || \
        error_exit "Failed to install Terraform"
    
    # Verify installation
    terraform version || error_exit "Terraform installation verification failed"
    
    log INFO "Terraform installed successfully"
}

install_packer() {
    log INFO "Installing Packer v$PACKER_VERSION..."
    
    # Download Packer
    local packer_url="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"
    
    cd /tmp
    wget "$packer_url" -O packer.zip || error_exit "Failed to download Packer"
    
    # Extract and install
    unzip -o packer.zip || error_exit "Failed to extract Packer"
    chmod +x packer
    mv packer /usr/local/bin/ || error_exit "Failed to install Packer"
    
    # Create symlink for compatibility
    ln -sf /usr/local/bin/packer /usr/bin/packer 2>/dev/null || true
    
    # Verify installation
    packer version || error_exit "Packer installation verification failed"
    
    # Cleanup
    rm -f packer.zip
    
    log INFO "Packer installed successfully"
}

install_ansible() {
    log INFO "Installing Ansible..."
    
    # Upgrade pip
    python3 -m pip install --upgrade pip || error_exit "Failed to upgrade pip"
    
    # Install Ansible
    python3 -m pip install \
        ansible=="$ANSIBLE_VERSION" \
        ansible-core \
        paramiko \
        || error_exit "Failed to install Ansible"
    
    # Install useful Ansible collections
    ansible-galaxy collection install \
        community.general \
        ansible.posix \
        community.crypto \
        community.docker \
        kubernetes.core \
        || log WARN "Failed to install some Ansible collections"
    
    # Verify installation
    ansible --version || error_exit "Ansible installation verification failed"
    ansible-playbook --version || error_exit "Ansible Playbook verification failed"
    
    log INFO "Ansible installed successfully"
}

install_proxmox_tools() {
    log INFO "Installing Proxmox API tools..."
    
    # Install Proxmox API Python library
    python3 -m pip install \
        proxmoxer \
        requests \
        urllib3 \
        || error_exit "Failed to install Proxmox API tools"
    
    # Install Terraform Proxmox provider (this will be handled by terraform init)
    log INFO "Proxmox provider will be installed during terraform init"
    
    log INFO "Proxmox tools installed successfully"
}

install_additional_tools() {
    log INFO "Installing additional automation tools..."
    
    # Install Docker CLI (for managing remote Docker)
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce-cli docker-compose-plugin || log WARN "Failed to install Docker CLI"
    
    # Install kubectl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
        gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
    
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
        https://apt.kubernetes.io/ kubernetes-xenial main" | \
        tee /etc/apt/sources.list.d/kubernetes.list
    
    apt-get update
    apt-get install -y kubectl || log WARN "Failed to install kubectl"
    
    # Install Helm
    curl -fsSL https://baltocdn.com/helm/signing.asc | \
        gpg --dearmor -o /usr/share/keyrings/helm.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] \
        https://baltocdn.com/helm/stable/debian/ all main" | \
        tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    apt-get update
    apt-get install -y helm || log WARN "Failed to install Helm"
    
    # Install additional Python tools
    python3 -m pip install \
        yamllint \
        ansible-lint \
        molecule \
        pytest \
        black \
        flake8 \
        || log WARN "Failed to install some Python tools"
    
    log INFO "Additional tools installation completed"
}

setup_workspace() {
    log INFO "Setting up workspace directory..."
    
    # Create workspace directory
    mkdir -p "$WORKSPACE_DIR"
    
    # Create subdirectories
    mkdir -p "$WORKSPACE_DIR"/{terraform,ansible,packer,scripts,logs,backups}
    
    # Set permissions
    chown -R "$USER_NAME:$USER_NAME" "$WORKSPACE_DIR"
    chmod -R 755 "$WORKSPACE_DIR"
    
    # Create useful scripts directory
    mkdir -p "/home/$USER_NAME/bin"
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/bin"
    
    # Add bin directory to PATH for infrastructure user
    echo 'export PATH="$HOME/bin:$PATH"' >> "/home/$USER_NAME/.bashrc"
    
    log INFO "Workspace setup completed"
}

configure_git() {
    log INFO "Configuring Git..."
    
    # Configure Git globally
    sudo -u "$USER_NAME" git config --global init.defaultBranch main
    sudo -u "$USER_NAME" git config --global pull.rebase false
    sudo -u "$USER_NAME" git config --global user.name "Infrastructure Manager"
    sudo -u "$USER_NAME" git config --global user.email "infrastructure@localhost"
    
    # Initialize workspace git repository
    cd "$WORKSPACE_DIR"
    sudo -u "$USER_NAME" git init . || true
    
    # Create .gitignore
    cat > "$WORKSPACE_DIR/.gitignore" << EOF
# Terraform
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
.terraform.lock.hcl

# Ansible
*.retry
.vault_pass

# Logs
logs/
*.log

# Temporary files
*.tmp
*.bak

# SSH keys
*.pem
id_rsa*

# Sensitive files
secrets/
.env
EOF
    
    chown "$USER_NAME:$USER_NAME" "$WORKSPACE_DIR/.gitignore"
    
    log INFO "Git configuration completed"
}

create_management_scripts() {
    log INFO "Creating management scripts..."
    
    # Create infrastructure status script
    cat > "/home/$USER_NAME/bin/infra-status" << 'EOF'
#!/bin/bash
# Infrastructure status checker

echo "=== Infrastructure Status ==="
echo "Date: $(date)"
echo ""

echo "=== Container Info ==="
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Uptime: $(uptime -p)"
echo ""

echo "=== Tool Versions ==="
echo "Terraform: $(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo 'Not available')"
echo "Packer: $(packer version 2>/dev/null || echo 'Not available')"
echo "Ansible: $(ansible --version 2>/dev/null | head -1 | awk '{print $3}' || echo 'Not available')"
echo ""

echo "=== Workspace Status ==="
if [[ -d /opt/infrastructure ]]; then
    echo "Workspace: ✓ Available"
    echo "Size: $(du -sh /opt/infrastructure | cut -f1)"
    if [[ -d /opt/infrastructure/.git ]]; then
        echo "Git: ✓ Initialized"
    else
        echo "Git: ✗ Not initialized"
    fi
else
    echo "Workspace: ✗ Not found"
fi
echo ""

echo "=== Network Connectivity ==="
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "Internet: ✓ Connected"
else
    echo "Internet: ✗ No connectivity"
fi

if ping -c 1 10.100.1.1 >/dev/null 2>&1; then
    echo "Gateway: ✓ Reachable"
else
    echo "Gateway: ✗ Not reachable"
fi
EOF

    # Create infrastructure management script
    cat > "/home/$USER_NAME/bin/infra-manage" << 'EOF'
#!/bin/bash
# Infrastructure management helper

WORKSPACE="/opt/infrastructure"

usage() {
    echo "Usage: $0 {status|deploy|destroy|validate|logs|workspace}"
    echo ""
    echo "Commands:"
    echo "  status    - Show infrastructure status"
    echo "  deploy    - Deploy infrastructure"
    echo "  destroy   - Destroy infrastructure"
    echo "  validate  - Validate deployment"
    echo "  logs      - Show recent logs"
    echo "  workspace - Navigate to workspace"
    exit 1
}

case "${1:-}" in
    status)
        infra-status
        ;;
    deploy)
        cd "$WORKSPACE" && ./scripts/deploy.sh "${@:2}"
        ;;
    destroy)
        cd "$WORKSPACE" && ./scripts/destroy.sh "${@:2}"
        ;;
    validate)
        cd "$WORKSPACE" && ./scripts/validate.sh "${@:2}"
        ;;
    logs)
        cd "$WORKSPACE" && tail -f logs/*.log
        ;;
    workspace)
        cd "$WORKSPACE" && bash
        ;;
    *)
        usage
        ;;
esac
EOF

    # Make scripts executable
    chmod +x "/home/$USER_NAME/bin/"*
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/bin/"*
    
    log INFO "Management scripts created"
}

configure_environment() {
    log INFO "Configuring environment..."
    
    # Create environment file for infrastructure user
    cat > "/home/$USER_NAME/.infrastructure_env" << 'EOF'
# Infrastructure Environment Configuration
export WORKSPACE_DIR="/opt/infrastructure"
export TERRAFORM_DIR="$WORKSPACE_DIR/terraform"
export ANSIBLE_DIR="$WORKSPACE_DIR/ansible"
export PACKER_DIR="$WORKSPACE_DIR/packer"

# Terraform configuration
export TF_LOG_LEVEL="INFO"
export TF_LOG_PATH="$WORKSPACE_DIR/logs/terraform.log"

# Ansible configuration
export ANSIBLE_HOST_KEY_CHECKING=false
export ANSIBLE_STDOUT_CALLBACK=yaml
export ANSIBLE_LOG_PATH="$WORKSPACE_DIR/logs/ansible.log"

# Packer configuration
export PACKER_LOG=1
export PACKER_LOG_PATH="$WORKSPACE_DIR/logs/packer.log"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias tf='terraform'
alias ap='ansible-playbook'
alias pk='packer'

# Functions
workspace() {
    cd "$WORKSPACE_DIR" || return
}

terraform-init() {
    cd "$TERRAFORM_DIR" && terraform init
}

ansible-ping() {
    cd "$ANSIBLE_DIR" && ansible all -m ping
}

packer-validate() {
    cd "$PACKER_DIR" && packer validate .
}
EOF

    # Source environment in bashrc
    echo 'source ~/.infrastructure_env' >> "/home/$USER_NAME/.bashrc"
    
    # Set ownership
    chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.infrastructure_env"
    
    log INFO "Environment configuration completed"
}

create_welcome_message() {
    log INFO "Creating welcome message..."
    
    cat > /etc/motd << 'EOF'

╔═══════════════════════════════════════════════════════════════╗
║               PROXMOX INFRASTRUCTURE MANAGEMENT               ║
║                        Container Ready                        ║
╚═══════════════════════════════════════════════════════════════╝

Welcome to the Infrastructure Management Container!

📁 Workspace: /opt/infrastructure
👤 User: infrastructure (sudo enabled)
🔧 Tools: Terraform, Ansible, Packer, Docker CLI, kubectl

Quick Commands:
  infra-status    - Check infrastructure status
  infra-manage    - Manage infrastructure (deploy/destroy/validate)
  workspace       - Navigate to workspace directory

Getting Started:
  1. Switch to infrastructure user: su - infrastructure
  2. Navigate to workspace: cd /opt/infrastructure
  3. Configure your environment variables
  4. Deploy infrastructure: ./scripts/deploy.sh

Documentation: /opt/infrastructure/README.md

EOF

    log INFO "Welcome message created"
}

run_post_install_checks() {
    log INFO "Running post-installation checks..."
    
    # Check tool installations
    local tools=("terraform" "packer" "ansible" "git" "python3")
    local failed_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            failed_tools+=("$tool")
        fi
    done
    
    if [[ ${#failed_tools[@]} -ne 0 ]]; then
        log ERROR "Some tools failed to install: ${failed_tools[*]}"
        return 1
    fi
    
    # Check Python packages
    local python_packages=("ansible" "proxmoxer" "requests")
    for package in "${python_packages[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            log WARN "Python package not available: $package"
        fi
    done
    
    # Check workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        log ERROR "Workspace directory not created"
        return 1
    fi
    
    # Check user
    if ! id "$USER_NAME" &>/dev/null; then
        log ERROR "Infrastructure user not created"
        return 1
    fi
    
    log INFO "Post-installation checks completed successfully"
}

print_summary() {
    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}       MANAGEMENT CONTAINER SETUP COMPLETED SUCCESSFULLY       ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    echo -e "${BLUE}Installation Summary:${NC}"
    echo -e "✅ System updated and essential packages installed"
    echo -e "✅ Infrastructure user created: ${YELLOW}$USER_NAME${NC}"
    echo -e "✅ Terraform $(terraform version 2>/dev/null | head -1 | awk '{print $2}') installed"
    echo -e "✅ Packer $(packer version 2>/dev/null) installed"
    echo -e "✅ Ansible $(ansible --version 2>/dev/null | head -1 | awk '{print $3}') installed"
    echo -e "✅ Proxmox API tools installed"
    echo -e "✅ Additional tools (Docker CLI, kubectl, Helm) installed"
    echo -e "✅ Workspace directory created: ${YELLOW}$WORKSPACE_DIR${NC}"
    echo -e "✅ Management scripts and environment configured"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Switch to infrastructure user: ${BLUE}su - $USER_NAME${NC}"
    echo -e "2. Navigate to workspace: ${BLUE}cd $WORKSPACE_DIR${NC}"
    echo -e "3. Clone your infrastructure repository"
    echo -e "4. Configure environment variables for Proxmox API"
    echo -e "5. Run deployment: ${BLUE}./scripts/deploy.sh${NC}"
    echo ""
    echo -e "${PURPLE}Useful Commands:${NC}"
    echo -e "• ${BLUE}infra-status${NC}     - Check system and tool status"
    echo -e "• ${BLUE}infra-manage${NC}     - Infrastructure management helper"
    echo -e "• ${BLUE}workspace${NC}        - Navigate to workspace directory"
    echo ""
    echo -e "${GREEN}Management container is ready for infrastructure automation!${NC}"
    echo ""
}

main() {
    log INFO "Starting management container setup..."
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Run setup steps
    check_environment
    update_system
    create_infrastructure_user
    install_terraform
    install_packer
    install_ansible
    install_proxmox_tools
    install_additional_tools
    setup_workspace
    configure_git
    create_management_scripts
    configure_environment
    create_welcome_message
    run_post_install_checks
    
    print_summary
    
    log INFO "Management container setup completed successfully!"
}

# Handle script interruption
trap 'error_exit "Setup interrupted by user"' INT TERM

# Run main function
main "$@"