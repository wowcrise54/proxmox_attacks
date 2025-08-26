#!/bin/bash

# Proxmox Infrastructure Deployment Script
# This script deploys the complete infrastructure using Terraform, Packer, and Ansible

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration files
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
PACKER_DIR="$PROJECT_ROOT/packer"

# Default configuration
ENVIRONMENT="dev"
DRY_RUN=false
SKIP_BOOTSTRAP=false
SKIP_TEMPLATES=false
SKIP_INFRASTRUCTURE=false
SKIP_CONFIGURATION=false
PARALLEL_BUILDS=true
FORCE_REBUILD=false

# Logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Functions
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

check_dependencies() {
    log INFO "Checking dependencies..."
    
    local deps=("terraform" "ansible" "packer" "jq" "curl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        error_exit "Missing dependencies: ${missing[*]}"
    fi
    
    log INFO "All dependencies satisfied"
}

check_proxmox_connection() {
    log INFO "Checking Proxmox connection..."
    
    if [[ -z "${PROXMOX_API_URL:-}" ]] || [[ -z "${PROXMOX_API_TOKEN_ID:-}" ]] || [[ -z "${PROXMOX_API_TOKEN_SECRET:-}" ]]; then
        error_exit "Proxmox API credentials not configured. Set PROXMOX_API_URL, PROXMOX_API_TOKEN_ID, and PROXMOX_API_TOKEN_SECRET"
    fi
    
    # Test connection
    if ! curl -k -s -H "Authorization: PVEAPIToken=${PROXMOX_API_TOKEN_ID}=${PROXMOX_API_TOKEN_SECRET}" \
        "${PROXMOX_API_URL}/version" >/dev/null; then
        error_exit "Cannot connect to Proxmox API at ${PROXMOX_API_URL}"
    fi
    
    log INFO "Proxmox connection verified"
}

run_bootstrap() {
    if [[ "$SKIP_BOOTSTRAP" == true ]]; then
        log INFO "Skipping bootstrap (--skip-bootstrap specified)"
        return
    fi
    
    log INFO "Running Proxmox bootstrap..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would execute bootstrap script"
        return
    fi
    
    local bootstrap_script="$PROJECT_ROOT/bootstrap/install-proxmox.sh"
    
    if [[ ! -f "$bootstrap_script" ]]; then
        error_exit "Bootstrap script not found: $bootstrap_script"
    fi
    
    if ! bash "$bootstrap_script"; then
        error_exit "Bootstrap failed"
    fi
    
    log INFO "Bootstrap completed successfully"
}

build_templates() {
    if [[ "$SKIP_TEMPLATES" == true ]]; then
        log INFO "Skipping template building (--skip-templates specified)"
        return
    fi
    
    log INFO "Building VM templates with Packer..."
    
    cd "$PACKER_DIR"
    
    local templates=("ubuntu-22-base.pkr.hcl" "docker-host.pkr.hcl")
    
    if [[ "$PARALLEL_BUILDS" == true ]]; then
        log INFO "Building templates in parallel..."
        local pids=()
        
        for template in "${templates[@]}"; do
            if [[ -f "$template" ]]; then
                log INFO "Starting build: $template"
                if [[ "$DRY_RUN" == true ]]; then
                    log INFO "DRY RUN: Would build template $template"
                else
                    (
                        packer build \
                            -var "proxmox_api_url=${PROXMOX_API_URL}" \
                            -var "proxmox_api_token_id=${PROXMOX_API_TOKEN_ID}" \
                            -var "proxmox_api_token_secret=${PROXMOX_API_TOKEN_SECRET}" \
                            "$template"
                    ) &
                    pids+=($!)
                fi
            fi
        done
        
        if [[ "$DRY_RUN" == false ]]; then
            for pid in "${pids[@]}"; do
                wait "$pid" || error_exit "Template build failed (PID: $pid)"
            done
        fi
    else
        log INFO "Building templates sequentially..."
        for template in "${templates[@]}"; do
            if [[ -f "$template" ]]; then
                log INFO "Building template: $template"
                if [[ "$DRY_RUN" == true ]]; then
                    log INFO "DRY RUN: Would build template $template"
                else
                    packer build \
                        -var "proxmox_api_url=${PROXMOX_API_URL}" \
                        -var "proxmox_api_token_id=${PROXMOX_API_TOKEN_ID}" \
                        -var "proxmox_api_token_secret=${PROXMOX_API_TOKEN_SECRET}" \
                        "$template" || error_exit "Template build failed: $template"
                fi
            fi
        done
    fi
    
    cd - >/dev/null
    log INFO "Template building completed"
}

deploy_infrastructure() {
    if [[ "$SKIP_INFRASTRUCTURE" == true ]]; then
        log INFO "Skipping infrastructure deployment (--skip-infrastructure specified)"
        return
    fi
    
    log INFO "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log INFO "Initializing Terraform..."
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run terraform init"
    else
        terraform init || error_exit "Terraform init failed"
    fi
    
    # Plan deployment
    log INFO "Planning infrastructure deployment..."
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run terraform plan"
    else
        terraform plan \
            -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
            -out="terraform-$ENVIRONMENT.plan" || error_exit "Terraform plan failed"
    fi
    
    # Apply deployment
    log INFO "Applying infrastructure deployment..."
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run terraform apply"
    else
        terraform apply "terraform-$ENVIRONMENT.plan" || error_exit "Terraform apply failed"
    fi
    
    cd - >/dev/null
    log INFO "Infrastructure deployment completed"
}

configure_infrastructure() {
    if [[ "$SKIP_CONFIGURATION" == true ]]; then
        log INFO "Skipping infrastructure configuration (--skip-configuration specified)"
        return
    fi
    
    log INFO "Configuring infrastructure with Ansible..."
    
    cd "$ANSIBLE_DIR"
    
    # Wait for systems to be ready
    log INFO "Waiting for systems to be ready..."
    if [[ "$DRY_RUN" == false ]]; then
        sleep 60
    fi
    
    # Test connectivity
    log INFO "Testing Ansible connectivity..."
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would test ansible connectivity"
    else
        ansible all -m ping || log WARN "Some hosts may not be reachable yet"
    fi
    
    # Run configuration playbook
    log INFO "Running configuration playbook..."
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run ansible-playbook site.yml"
    else
        ansible-playbook site.yml \
            --extra-vars "environment=$ENVIRONMENT" \
            --become || error_exit "Ansible configuration failed"
    fi
    
    cd - >/dev/null
    log INFO "Infrastructure configuration completed"
}

validate_deployment() {
    log INFO "Validating deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN: Would run validation tests"
        return
    fi
    
    # Run validation script if it exists
    local validation_script="$PROJECT_ROOT/scripts/validate.sh"
    if [[ -f "$validation_script" ]]; then
        bash "$validation_script" || log WARN "Validation script reported issues"
    fi
    
    log INFO "Deployment validation completed"
}

print_summary() {
    log INFO "Deployment Summary"
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}Proxmox Infrastructure Deployment Complete${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo -e "Environment: ${BLUE}$ENVIRONMENT${NC}"
    echo -e "Deployment time: ${BLUE}$(date)${NC}"
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Verify infrastructure: scripts/validate.sh"
    echo "2. Access management container: pct enter 100"
    echo "3. View Terraform outputs: cd terraform && terraform output"
    echo "4. Check Ansible inventory: cd ansible && ansible-inventory --list"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy Proxmox infrastructure using Terraform, Packer, and Ansible.

OPTIONS:
    -e, --environment ENV     Set environment (dev/staging/prod) [default: dev]
    -n, --dry-run            Show what would be done without executing
    --skip-bootstrap         Skip Proxmox bootstrap
    --skip-templates         Skip Packer template building
    --skip-infrastructure    Skip Terraform infrastructure deployment
    --skip-configuration     Skip Ansible configuration
    --sequential             Build templates sequentially instead of parallel
    --force-rebuild          Force rebuild of existing templates
    -v, --verbose            Enable verbose output
    -h, --help              Show this help message

ENVIRONMENT VARIABLES:
    PROXMOX_API_URL          Proxmox API URL (required)
    PROXMOX_API_TOKEN_ID     Proxmox API Token ID (required)
    PROXMOX_API_TOKEN_SECRET Proxmox API Token Secret (required)

EXAMPLES:
    $0                       Deploy with default settings
    $0 -e prod               Deploy to production environment
    $0 --dry-run             Show what would be deployed
    $0 --skip-bootstrap      Skip bootstrap, deploy infrastructure only

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
            --skip-bootstrap)
                SKIP_BOOTSTRAP=true
                shift
                ;;
            --skip-templates)
                SKIP_TEMPLATES=true
                shift
                ;;
            --skip-infrastructure)
                SKIP_INFRASTRUCTURE=true
                shift
                ;;
            --skip-configuration)
                SKIP_CONFIGURATION=true
                shift
                ;;
            --sequential)
                PARALLEL_BUILDS=false
                shift
                ;;
            --force-rebuild)
                FORCE_REBUILD=true
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
    
    log INFO "Starting Proxmox Infrastructure Deployment"
    log INFO "Environment: $ENVIRONMENT"
    log INFO "Dry run: $DRY_RUN"
    
    # Pre-flight checks
    check_dependencies
    check_proxmox_connection
    
    # Deployment phases
    run_bootstrap
    build_templates
    deploy_infrastructure
    configure_infrastructure
    validate_deployment
    
    print_summary
    
    log INFO "Deployment completed successfully!"
}

# Handle script interruption
trap 'error_exit "Deployment interrupted by user"' INT TERM

# Run main function
main "$@"