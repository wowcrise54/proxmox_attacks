#!/bin/bash

# Proxmox Infrastructure Destruction Script
# This script safely destroys the infrastructure in reverse order

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ENVIRONMENT="dev"
DRY_RUN=false
FORCE_DESTROY=false
KEEP_TEMPLATES=false
CONFIRM=true

# Logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/destroy-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        *)     echo -e "$message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    exit 1
}

confirm_destroy() {
    if [[ "$CONFIRM" == false ]]; then
        return 0
    fi
    
    echo -e "${RED}WARNING: This will destroy all infrastructure in environment: $ENVIRONMENT${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    echo "Resources that will be destroyed:"
    echo "- All VMs and containers"
    echo "- SDN networks and subnets"
    echo "- Storage volumes"
    if [[ "$KEEP_TEMPLATES" == false ]]; then
        echo "- VM templates"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " response
    
    if [[ "$response" != "yes" ]]; then
        log INFO "Destruction cancelled by user"
        exit 0
    fi
}

stop_services() {
    log INFO "Stopping services and containers..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would stop all running services"
        return
    fi
    
    # Stop VMs gracefully
    log INFO "Stopping VMs gracefully..."
    local vm_ids=(201 211 221)  # From terraform variables
    
    for vm_id in "${vm_ids[@]}"; do
        if qm status "$vm_id" >/dev/null 2>&1; then
            if qm status "$vm_id" | grep -q "running"; then
                log INFO "Stopping VM $vm_id..."
                qm shutdown "$vm_id" --timeout 60 || qm stop "$vm_id"
            fi
        fi
    done
    
    # Stop management container
    local container_id=100
    if pct status "$container_id" >/dev/null 2>&1; then
        if pct status "$container_id" | grep -q "running"; then
            log INFO "Stopping container $container_id..."
            pct shutdown "$container_id" --timeout 60 || pct stop "$container_id"
        fi
    fi
    
    log INFO "Services stopped"
}

destroy_terraform_infrastructure() {
    log INFO "Destroying Terraform-managed infrastructure..."
    
    cd "$TERRAFORM_DIR"
    
    if [[ ! -f "terraform.tfstate" ]]; then
        log WARN "No Terraform state found, skipping Terraform destroy"
        cd - >/dev/null
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run terraform destroy"
        cd - >/dev/null
        return
    fi
    
    # Plan destruction
    log INFO "Planning infrastructure destruction..."
    terraform plan -destroy \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -out="destroy-$ENVIRONMENT.plan" || error_exit "Terraform destroy plan failed"
    
    # Apply destruction
    log INFO "Applying infrastructure destruction..."
    if [[ "$FORCE_DESTROY" == true ]]; then
        terraform apply -auto-approve "destroy-$ENVIRONMENT.plan" || error_exit "Terraform destroy failed"
    else
        terraform apply "destroy-$ENVIRONMENT.plan" || error_exit "Terraform destroy failed"
    fi
    
    cd - >/dev/null
    log INFO "Terraform infrastructure destroyed"
}

cleanup_templates() {
    if [[ "$KEEP_TEMPLATES" == true ]]; then
        log INFO "Keeping VM templates (--keep-templates specified)"
        return
    fi
    
    log INFO "Cleaning up VM templates..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would remove VM templates"
        return
    fi
    
    local templates=("ubuntu-22-04-template" "docker-host-template")
    
    for template in "${templates[@]}"; do
        # Find template by name
        local template_id=$(qm list | grep "$template" | awk '{print $1}' | head -n1)
        
        if [[ -n "$template_id" ]]; then
            log INFO "Removing template: $template (ID: $template_id)"
            qm destroy "$template_id" --purge || log WARN "Failed to remove template $template"
        else
            log INFO "Template not found: $template"
        fi
    done
    
    log INFO "Template cleanup completed"
}

cleanup_sdn() {
    log INFO "Cleaning up SDN configuration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would clean up SDN configuration"
        return
    fi
    
    # Remove subnets
    local vnets=("management-net" "infrastructure-net" "services-net")
    local subnets=("10.100.1.0/24" "10.100.2.0/24" "10.100.3.0/24")
    
    for i in "${!vnets[@]}"; do
        local vnet="${vnets[$i]}"
        local subnet="${subnets[$i]}"
        
        if pvesh get "/cluster/sdn/vnets/$vnet/subnets/$subnet" >/dev/null 2>&1; then
            log INFO "Removing subnet $subnet from $vnet..."
            pvesh delete "/cluster/sdn/vnets/$vnet/subnets/$subnet" || log WARN "Failed to remove subnet $subnet"
        fi
    done
    
    # Remove VNETs
    for vnet in "${vnets[@]}"; do
        if pvesh get "/cluster/sdn/vnets/$vnet" >/dev/null 2>&1; then
            log INFO "Removing VNET: $vnet"
            pvesh delete "/cluster/sdn/vnets/$vnet" || log WARN "Failed to remove VNET $vnet"
        fi
    done
    
    # Remove SDN Zone
    local zone="infrastructure-zone"
    if pvesh get "/cluster/sdn/zones/$zone" >/dev/null 2>&1; then
        log INFO "Removing SDN zone: $zone"
        pvesh delete "/cluster/sdn/zones/$zone" || log WARN "Failed to remove SDN zone $zone"
    fi
    
    # Apply SDN changes
    log INFO "Applying SDN configuration changes..."
    pvesh set /cluster/sdn --apply 1 || log WARN "Failed to apply SDN changes"
    
    log INFO "SDN cleanup completed"
}

cleanup_storage() {
    log INFO "Cleaning up storage artifacts..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would clean up storage artifacts"
        return
    fi
    
    # Clean up any remaining disks and ISO files
    log INFO "Removing unused storage..."
    
    # This is handled by Terraform destroy, but we can add manual cleanup here if needed
    log INFO "Storage cleanup completed"
}

cleanup_logs() {
    log INFO "Cleaning up deployment logs..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would clean up old logs"
        return
    fi
    
    # Keep last 10 log files
    cd "$LOG_DIR"
    ls -t *.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    cd - >/dev/null
    
    log INFO "Log cleanup completed"
}

print_summary() {
    echo -e "${GREEN}=================================${NC}"
    echo -e "${GREEN}Infrastructure Destruction Complete${NC}"
    echo -e "${GREEN}=================================${NC}"
    echo -e "Environment: ${BLUE}$ENVIRONMENT${NC}"
    echo -e "Destruction time: ${BLUE}$(date)${NC}"
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}Summary:${NC}"
    echo "- Infrastructure destroyed"
    if [[ "$KEEP_TEMPLATES" == false ]]; then
        echo "- VM templates removed"
    else
        echo "- VM templates preserved"
    fi
    echo "- SDN configuration cleaned"
    echo "- Storage artifacts removed"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Destroy Proxmox infrastructure deployed with Terraform.

OPTIONS:
    -e, --environment ENV    Set environment (dev/staging/prod) [default: dev]
    -n, --dry-run           Show what would be destroyed without executing
    --force                 Skip confirmation and force destruction
    --no-confirm            Skip confirmation prompt
    --keep-templates        Keep VM templates during destruction
    -v, --verbose           Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                      Destroy infrastructure with confirmation
    $0 --force             Destroy without confirmation
    $0 --dry-run           Show what would be destroyed
    $0 --keep-templates    Destroy infrastructure but keep templates

EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DESTROY=true
                CONFIRM=false
                shift
                ;;
            --no-confirm)
                CONFIRM=false
                shift
                ;;
            --keep-templates)
                KEEP_TEMPLATES=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Setup logging
    mkdir -p "$LOG_DIR"
    
    log INFO "Starting infrastructure destruction"
    log INFO "Environment: $ENVIRONMENT"
    log INFO "Dry run: $DRY_RUN"
    
    # Confirmation
    confirm_destroy
    
    # Destruction phases (in reverse order of creation)
    stop_services
    destroy_terraform_infrastructure
    cleanup_templates
    cleanup_sdn
    cleanup_storage
    cleanup_logs
    
    print_summary
    
    log INFO "Destruction completed successfully!"
}

# Handle script interruption
trap 'error_exit "Destruction interrupted by user"' INT TERM

# Run main function
main "$@"