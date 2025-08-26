#!/bin/bash

# Container Management Utility
# This script provides easy management of the infrastructure container

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DEFAULT_CONTAINER_ID="100"
CONTAINER_ID="${CONTAINER_ID:-$DEFAULT_CONTAINER_ID}"

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

check_container_exists() {
    if ! pct list 2>/dev/null | grep -q "^$CONTAINER_ID "; then
        error_exit "Container $CONTAINER_ID does not exist"
    fi
}

container_status() {
    log INFO "Container Status for ID: $CONTAINER_ID"
    echo ""
    
    # Basic container info
    if pct config "$CONTAINER_ID" >/dev/null 2>&1; then
        echo -e "${BLUE}Configuration:${NC}"
        pct config "$CONTAINER_ID" | grep -E "(hostname|memory|cores|net0)" | sed 's/^/  /'
        echo ""
    fi
    
    # Status
    local status=$(pct status "$CONTAINER_ID" 2>/dev/null | awk '{print $2}')
    echo -e "${BLUE}Status:${NC} $status"
    
    if [[ "$status" == "running" ]]; then
        # Resource usage
        echo ""
        echo -e "${BLUE}Resource Usage:${NC}"
        pct exec "$CONTAINER_ID" -- bash -c '
            echo "  CPU Load: $(cat /proc/loadavg | cut -d" " -f1-3)"
            echo "  Memory: $(free -h | grep "^Mem:" | awk "{printf \"%.1fG / %.1fG (%.1f%%)\", \$3/1024, \$2/1024, \$3/\$2*100}")"
            echo "  Disk: $(df -h / | tail -1 | awk "{print \$3 \" / \" \$2 \" (\" \$5 \")\"}")"
        ' 2>/dev/null || echo "  Unable to fetch resource usage"
        
        # Network info
        local container_ip=$(pct exec "$CONTAINER_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "Unknown")
        echo "  IP Address: $container_ip"
        
        # Check tools
        echo ""
        echo -e "${BLUE}Installed Tools:${NC}"
        for tool in terraform packer ansible git; do
            if pct exec "$CONTAINER_ID" -- command -v "$tool" >/dev/null 2>&1; then
                local version=$(pct exec "$CONTAINER_ID" -- "$tool" --version 2>/dev/null | head -1 || echo "Unknown")
                echo "  ✓ $tool: $version"
            else
                echo "  ✗ $tool: Not installed"
            fi
        done
        
        # Check workspace
        echo ""
        echo -e "${BLUE}Workspace:${NC}"
        if pct exec "$CONTAINER_ID" -- test -d "/opt/infrastructure" 2>/dev/null; then
            local workspace_size=$(pct exec "$CONTAINER_ID" -- du -sh /opt/infrastructure 2>/dev/null | cut -f1 || echo "Unknown")
            echo "  ✓ /opt/infrastructure ($workspace_size)"
            
            # Check for key files
            local key_files=("terraform/main.tf" "ansible/site.yml" "scripts/deploy.sh" ".env")
            for file in "${key_files[@]}"; do
                if pct exec "$CONTAINER_ID" -- test -f "/opt/infrastructure/$file" 2>/dev/null; then
                    echo "  ✓ $file"
                else
                    echo "  ✗ $file"
                fi
            done
        else
            echo "  ✗ /opt/infrastructure: Not found"
        fi
    fi
    
    echo ""
}

container_start() {
    log INFO "Starting container $CONTAINER_ID..."
    
    check_container_exists
    
    local status=$(pct status "$CONTAINER_ID" | awk '{print $2}')
    
    if [[ "$status" == "running" ]]; then
        log INFO "Container is already running"
        return
    fi
    
    pct start "$CONTAINER_ID" || error_exit "Failed to start container"
    
    # Wait for container to be ready
    log INFO "Waiting for container to be ready..."
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if pct exec "$CONTAINER_ID" -- echo "ready" >/dev/null 2>&1; then
            log INFO "Container is ready"
            return
        fi
        sleep 2
        ((attempts++))
    done
    
    log WARN "Container started but may not be fully ready"
}

container_stop() {
    log INFO "Stopping container $CONTAINER_ID..."
    
    check_container_exists
    
    local status=$(pct status "$CONTAINER_ID" | awk '{print $2}')
    
    if [[ "$status" == "stopped" ]]; then
        log INFO "Container is already stopped"
        return
    fi
    
    # Try graceful shutdown first
    if pct shutdown "$CONTAINER_ID" --timeout 60; then
        log INFO "Container stopped gracefully"
    else
        log WARN "Graceful shutdown failed, forcing stop..."
        pct stop "$CONTAINER_ID" || error_exit "Failed to stop container"
        log INFO "Container stopped forcefully"
    fi
}

container_restart() {
    log INFO "Restarting container $CONTAINER_ID..."
    container_stop
    sleep 2
    container_start
}

container_enter() {
    log INFO "Entering container $CONTAINER_ID..."
    
    check_container_exists
    container_start
    
    echo -e "${BLUE}Entering container as root. Use 'su - infrastructure' to switch to infrastructure user.${NC}"
    pct enter "$CONTAINER_ID"
}

container_shell() {
    log INFO "Starting shell in container $CONTAINER_ID as infrastructure user..."
    
    check_container_exists
    container_start
    
    # Check if infrastructure user exists
    if ! pct exec "$CONTAINER_ID" -- id infrastructure >/dev/null 2>&1; then
        log WARN "Infrastructure user not found, using root"
        pct enter "$CONTAINER_ID"
    else
        pct exec "$CONTAINER_ID" -- su - infrastructure
    fi
}

container_exec() {
    local command="$*"
    if [[ -z "$command" ]]; then
        error_exit "No command specified"
    fi
    
    log INFO "Executing command in container $CONTAINER_ID: $command"
    
    check_container_exists
    container_start
    
    pct exec "$CONTAINER_ID" -- bash -c "$command"
}

container_logs() {
    log INFO "Showing container logs..."
    
    # System logs
    echo -e "${BLUE}=== Container System Logs ===${NC}"
    journalctl -u pve-container@"$CONTAINER_ID" --no-pager -n 50 2>/dev/null || \
        echo "No system logs available"
    
    # Application logs if container is running
    if pct status "$CONTAINER_ID" | grep -q "running"; then
        echo ""
        echo -e "${BLUE}=== Infrastructure Logs ===${NC}"
        if pct exec "$CONTAINER_ID" -- test -d "/opt/infrastructure/logs" 2>/dev/null; then
            pct exec "$CONTAINER_ID" -- find /opt/infrastructure/logs -name "*.log" -type f -exec tail -5 {} + 2>/dev/null || \
                echo "No infrastructure logs found"
        else
            echo "Infrastructure logs directory not found"
        fi
    fi
}

container_backup() {
    local backup_storage="${1:-local}"
    local backup_mode="${2:-stop}"
    
    log INFO "Creating backup of container $CONTAINER_ID..."
    
    check_container_exists
    
    # Create backup using vzdump
    vzdump "$CONTAINER_ID" \
        --storage "$backup_storage" \
        --mode "$backup_mode" \
        --compress gzip \
        --notes "Infrastructure container backup - $(date)" \
        || error_exit "Backup failed"
    
    log INFO "Backup completed successfully"
}

container_clone() {
    local target_id="$1"
    local target_name="${2:-infrastructure-mgmt-clone}"
    
    if [[ -z "$target_id" ]]; then
        error_exit "Target container ID required"
    fi
    
    log INFO "Cloning container $CONTAINER_ID to $target_id..."
    
    check_container_exists
    
    # Check if target ID is available
    if pct list | grep -q "^$target_id "; then
        error_exit "Target container ID $target_id already exists"
    fi
    
    # Clone container
    pct clone "$CONTAINER_ID" "$target_id" \
        --hostname "$target_name" \
        --full \
        || error_exit "Clone failed"
    
    log INFO "Container cloned successfully to ID $target_id"
}

usage() {
    cat <<EOF
Usage: $0 <command> [arguments]

Manage infrastructure container (ID: $CONTAINER_ID)

Commands:
    status                  Show container status and information
    start                   Start the container
    stop                    Stop the container
    restart                 Restart the container
    enter                   Enter container shell as root
    shell                   Enter container as infrastructure user
    exec <command>          Execute command in container
    logs                    Show container logs
    backup [storage] [mode] Create container backup
    clone <id> [name]       Clone container to new ID
    
Environment Variables:
    CONTAINER_ID           Container ID to manage (default: $DEFAULT_CONTAINER_ID)

Examples:
    $0 status               # Show container status
    $0 start                # Start container
    $0 shell                # Enter as infrastructure user
    $0 exec "infra-status"  # Run command in container
    $0 backup local stop    # Create backup on local storage
    $0 clone 101 "test-mgmt" # Clone to container 101

EOF
}

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        status)
            container_status
            ;;
        start)
            container_start
            ;;
        stop)
            container_stop
            ;;
        restart)
            container_restart
            ;;
        enter)
            container_enter
            ;;
        shell)
            container_shell
            ;;
        exec)
            container_exec "$@"
            ;;
        logs)
            container_logs
            ;;
        backup)
            container_backup "$@"
            ;;
        clone)
            container_clone "$@"
            ;;
        *)
            error_exit "Unknown command: $command"
            ;;
    esac
}

# Handle script interruption
trap 'error_exit "Operation interrupted by user"' INT TERM

# Check if running on Proxmox
if ! command -v pct >/dev/null 2>&1; then
    error_exit "This script must be run on a Proxmox VE host"
fi

# Run main function
main "$@"