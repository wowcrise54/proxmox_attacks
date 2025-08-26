#!/bin/bash

# Remote Management Container Configuration Script
# This script configures an existing LXC container with automation tools remotely

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DEFAULT_CONTAINER_ID="100"
CONTAINER_ID="${1:-$DEFAULT_CONTAINER_ID}"
SETUP_SCRIPT="setup-management-container.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        *)     echo -e "$message" ;;
    esac
}

error_exit() {
    log ERROR "$1"
    exit 1
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if running on Proxmox host
    if ! command -v pct >/dev/null 2>&1; then
        error_exit "This script must be run on a Proxmox VE host (pct command not found)"
    fi
    
    # Check if container exists
    if ! pct list | grep -q "^$CONTAINER_ID "; then
        error_exit "Container $CONTAINER_ID does not exist"
    fi
    
    # Check if setup script exists
    if [[ ! -f "$SCRIPT_DIR/$SETUP_SCRIPT" ]]; then
        error_exit "Setup script not found: $SCRIPT_DIR/$SETUP_SCRIPT"
    fi
    
    log INFO "Prerequisites check completed"
}

check_container_status() {
    log INFO "Checking container status..."
    
    local status=$(pct status "$CONTAINER_ID" | awk '{print $2}')
    
    case $status in
        "running")
            log INFO "Container $CONTAINER_ID is running"
            ;;
        "stopped")
            log INFO "Container $CONTAINER_ID is stopped, starting..."
            pct start "$CONTAINER_ID" || error_exit "Failed to start container"
            sleep 10
            ;;
        *)
            error_exit "Container $CONTAINER_ID has unexpected status: $status"
            ;;
    esac
}

test_container_connectivity() {
    log INFO "Testing container connectivity..."
    
    # Test basic connectivity
    if ! pct exec "$CONTAINER_ID" -- echo "Container is accessible" >/dev/null 2>&1; then
        error_exit "Cannot execute commands in container $CONTAINER_ID"
    fi
    
    # Test internet connectivity
    if ! pct exec "$CONTAINER_ID" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log WARN "Container has no internet connectivity - some installations may fail"
    fi
    
    log INFO "Container connectivity test completed"
}

copy_setup_script() {
    log INFO "Copying setup script to container..."
    
    # Copy the setup script to the container
    pct push "$CONTAINER_ID" "$SCRIPT_DIR/$SETUP_SCRIPT" "/tmp/$SETUP_SCRIPT" || \
        error_exit "Failed to copy setup script to container"
    
    # Make script executable
    pct exec "$CONTAINER_ID" -- chmod +x "/tmp/$SETUP_SCRIPT" || \
        error_exit "Failed to make setup script executable"
    
    log INFO "Setup script copied successfully"
}

run_container_setup() {
    log INFO "Running setup script in container..."
    
    # Execute the setup script inside the container
    if pct exec "$CONTAINER_ID" -- "/tmp/$SETUP_SCRIPT"; then
        log INFO "Container setup completed successfully"
    else
        error_exit "Container setup script failed"
    fi
    
    # Cleanup temporary script
    pct exec "$CONTAINER_ID" -- rm -f "/tmp/$SETUP_SCRIPT" || \
        log WARN "Failed to cleanup temporary setup script"
}

copy_project_files() {
    log INFO "Copying project files to container..."
    
    local project_root="$(dirname "$SCRIPT_DIR")"
    local workspace_dir="/opt/infrastructure"
    
    # Create workspace directory in container
    pct exec "$CONTAINER_ID" -- mkdir -p "$workspace_dir" || \
        error_exit "Failed to create workspace directory"
    
    # Copy project files (excluding sensitive files)
    local files_to_copy=(
        "terraform"
        "ansible" 
        "packer"
        "scripts"
        "README.md"
        "SETUP.md"
    )
    
    for item in "${files_to_copy[@]}"; do
        if [[ -e "$project_root/$item" ]]; then
            log INFO "Copying $item..."
            # Use tar to preserve permissions and structure
            tar -C "$project_root" -cf - "$item" | \
                pct exec "$CONTAINER_ID" -- tar -C "$workspace_dir" -xf - || \
                log WARN "Failed to copy $item"
        fi
    done
    
    # Set proper ownership
    pct exec "$CONTAINER_ID" -- chown -R infrastructure:infrastructure "$workspace_dir" || \
        log WARN "Failed to set ownership of workspace"
    
    log INFO "Project files copied successfully"
}

configure_environment_variables() {
    log INFO "Setting up environment variables template..."
    
    # Create environment variables template
    pct exec "$CONTAINER_ID" -- tee "/opt/infrastructure/.env.template" >/dev/null << 'EOF'
# Proxmox Infrastructure Environment Variables
# Copy this file to .env and configure your settings

# Proxmox API Configuration (Required)
export PROXMOX_API_URL="https://your-proxmox-host:8006/api2/json"
export PROXMOX_API_TOKEN_ID="your-token-id"
export PROXMOX_API_TOKEN_SECRET="your-token-secret"

# Optional Configuration
export PROXMOX_NODE="pve"
export TF_VAR_target_node="pve"
export TF_VAR_environment="dev"

# Logging
export TF_LOG="INFO"
export ANSIBLE_LOG_PATH="/opt/infrastructure/logs/ansible.log"
export PACKER_LOG=1

# Usage:
# 1. Copy this file: cp .env.template .env
# 2. Edit .env with your actual values
# 3. Source the file: source .env
# 4. Run deployments: ./scripts/deploy.sh
EOF

    # Create sourcing instruction
    pct exec "$CONTAINER_ID" -- tee "/opt/infrastructure/README-SETUP.md" >/dev/null << 'EOF'
# Container Setup Complete!

## Quick Start

1. **Configure Environment Variables:**
   ```bash
   cd /opt/infrastructure
   cp .env.template .env
   nano .env  # Edit with your Proxmox API credentials
   source .env
   ```

2. **Test Configuration:**
   ```bash
   ./scripts/validate.sh --quick
   ```

3. **Deploy Infrastructure:**
   ```bash
   ./scripts/deploy.sh
   ```

## Environment Variables Required

- `PROXMOX_API_URL`: Your Proxmox API endpoint
- `PROXMOX_API_TOKEN_ID`: API Token ID  
- `PROXMOX_API_TOKEN_SECRET`: API Token Secret

## Useful Commands

- `infra-status`: Check system status
- `infra-manage deploy`: Deploy infrastructure
- `infra-manage validate`: Validate deployment
- `workspace`: Navigate to workspace

## Support

Check the main README.md for detailed documentation and troubleshooting.
EOF

    log INFO "Environment variables template created"
}

validate_container_setup() {
    log INFO "Validating container setup..."
    
    # Check if tools are installed
    local tools=("terraform" "packer" "ansible")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! pct exec "$CONTAINER_ID" -- command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log ERROR "Some tools are missing: ${missing_tools[*]}"
        return 1
    fi
    
    # Check if workspace exists
    if ! pct exec "$CONTAINER_ID" -- test -d "/opt/infrastructure"; then
        log ERROR "Workspace directory not found"
        return 1
    fi
    
    # Check if infrastructure user exists
    if ! pct exec "$CONTAINER_ID" -- id infrastructure >/dev/null 2>&1; then
        log ERROR "Infrastructure user not found"
        return 1
    fi
    
    log INFO "Container validation completed successfully"
}

print_summary() {
    local container_ip=$(pct exec "$CONTAINER_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "Unknown")
    
    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}    REMOTE CONTAINER CONFIGURATION COMPLETED SUCCESSFULLY      ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    echo -e "${BLUE}Container Information:${NC}"
    echo -e "Container ID: ${YELLOW}$CONTAINER_ID${NC}"
    echo -e "Container IP: ${YELLOW}$container_ip${NC}"
    echo -e "Workspace: ${YELLOW}/opt/infrastructure${NC}"
    echo -e "User: ${YELLOW}infrastructure${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Access container: ${BLUE}pct enter $CONTAINER_ID${NC}"
    echo -e "2. Switch to infrastructure user: ${BLUE}su - infrastructure${NC}"
    echo -e "3. Navigate to workspace: ${BLUE}cd /opt/infrastructure${NC}"
    echo -e "4. Configure environment: ${BLUE}cp .env.template .env && nano .env${NC}"
    echo -e "5. Source environment: ${BLUE}source .env${NC}"
    echo -e "6. Deploy infrastructure: ${BLUE}./scripts/deploy.sh${NC}"
    echo ""
    echo -e "${BLUE}Quick Access Commands:${NC}"
    echo -e "• ${BLUE}pct enter $CONTAINER_ID${NC}                    - Access container"
    echo -e "• ${BLUE}pct exec $CONTAINER_ID -- infra-status${NC}     - Check status"
    echo -e "• ${BLUE}pct exec $CONTAINER_ID -- su - infrastructure${NC} - Switch user"
    echo ""
    echo -e "${GREEN}Container is ready for infrastructure automation!${NC}"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [CONTAINER_ID]

Configure an existing LXC container with infrastructure automation tools.

ARGUMENTS:
    CONTAINER_ID    Container ID to configure (default: $DEFAULT_CONTAINER_ID)

EXAMPLES:
    $0              # Configure container 100
    $0 101          # Configure container 101

REQUIREMENTS:
    - Must be run on Proxmox VE host
    - Target container must exist
    - Container must have network connectivity

EOF
}

main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    
    log INFO "Starting remote container configuration..."
    log INFO "Target container ID: $CONTAINER_ID"
    
    # Run configuration steps
    check_prerequisites
    check_container_status  
    test_container_connectivity
    copy_setup_script
    run_container_setup
    copy_project_files
    configure_environment_variables
    validate_container_setup
    
    print_summary
    
    log INFO "Remote container configuration completed successfully!"
}

# Handle script interruption
trap 'error_exit "Configuration interrupted by user"' INT TERM

# Run main function
main "$@"