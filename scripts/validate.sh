#!/bin/bash

# Proxmox Infrastructure Validation Script
# This script validates the deployed infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="dev"
VERBOSE=false
QUICK_CHECK=false

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/validation-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        PASS)  echo -e "${GREEN}[PASS]${NC} $message" ;;
        FAIL)  echo -e "${RED}[FAIL]${NC} $message" ;;
        *)     echo -e "$message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    
    if [[ "$VERBOSE" == true ]]; then
        log INFO "Running test: $test_name"
        log INFO "Command: $test_command"
    fi
    
    if eval "$test_command" >/dev/null 2>&1; then
        log PASS "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log FAIL "$test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_proxmox_api() {
    log INFO "Testing Proxmox API connectivity..."
    
    if [[ -z "${PROXMOX_API_URL:-}" ]]; then
        log FAIL "Proxmox API URL not configured"
        ((TESTS_FAILED++))
        ((TESTS_TOTAL++))
        return 1
    fi
    
    run_test "Proxmox API - Version check" \
        "curl -k -s -H 'Authorization: PVEAPIToken=${PROXMOX_API_TOKEN_ID}=${PROXMOX_API_TOKEN_SECRET}' '${PROXMOX_API_URL}/version'"
    
    run_test "Proxmox API - Node status" \
        "curl -k -s -H 'Authorization: PVEAPIToken=${PROXMOX_API_TOKEN_ID}=${PROXMOX_API_TOKEN_SECRET}' '${PROXMOX_API_URL}/nodes' | jq -r '.[].status' | grep -q 'online'"
}

test_sdn_configuration() {
    log INFO "Testing SDN configuration..."
    
    local zone="infrastructure-zone"
    local vnets=("management-net" "infrastructure-net" "services-net")
    
    run_test "SDN Zone - $zone exists" \
        "pvesh get /cluster/sdn/zones/$zone"
    
    for vnet in "${vnets[@]}"; do
        run_test "VNET - $vnet exists" \
            "pvesh get /cluster/sdn/vnets/$vnet"
    done
    
    run_test "SDN Status - No errors" \
        "pvesh get /cluster/sdn/status | jq -r '.[] | select(.status != \"ok\")' | test ! -s"
}

test_management_container() {
    log INFO "Testing management container..."
    
    local container_id=100
    
    run_test "Management container - Exists" \
        "pct list | grep -q '^$container_id '"
    
    run_test "Management container - Running" \
        "pct status $container_id | grep -q 'running'"
    
    run_test "Management container - Network connectivity" \
        "pct exec $container_id -- ping -c 1 8.8.8.8"
    
    # Test tools installation
    run_test "Management container - Terraform installed" \
        "pct exec $container_id -- terraform version"
    
    run_test "Management container - Ansible installed" \
        "pct exec $container_id -- ansible --version"
    
    run_test "Management container - Packer installed" \
        "pct exec $container_id -- packer version"
}

test_vm_templates() {
    log INFO "Testing VM templates..."
    
    local templates=("ubuntu-22-04-template" "docker-host-template")
    
    for template in "${templates[@]}"; do
        run_test "Template - $template exists" \
            "qm list | grep -q '$template'"
    done
}

test_infrastructure_vms() {
    log INFO "Testing infrastructure VMs..."
    
    local vms=(
        "201:docker-host-01"
        "211:k8s-master-01" 
        "221:k8s-worker-01"
    )
    
    for vm_info in "${vms[@]}"; do
        local vm_id="${vm_info%:*}"
        local vm_name="${vm_info#*:}"
        
        run_test "VM - $vm_name ($vm_id) exists" \
            "qm list | grep -q '^$vm_id '"
        
        run_test "VM - $vm_name ($vm_id) running" \
            "qm status $vm_id | grep -q 'running'"
    done
}

test_network_connectivity() {
    log INFO "Testing network connectivity..."
    
    # Test management network
    run_test "Network - Management container reachable" \
        "ping -c 1 10.100.1.10"
    
    # Test infrastructure network
    local infra_ips=("10.100.2.101" "10.100.2.111" "10.100.2.121")
    
    for ip in "${infra_ips[@]}"; do
        run_test "Network - Infrastructure VM $ip reachable" \
            "ping -c 1 $ip"
    done
    
    # Test internet connectivity from VMs
    if [[ "$QUICK_CHECK" == false ]]; then
        run_test "Network - Docker host internet access" \
            "ssh -o StrictHostKeyChecking=no ubuntu@10.100.2.101 'ping -c 1 8.8.8.8'"
        
        run_test "Network - K8s master internet access" \
            "ssh -o StrictHostKeyChecking=no ubuntu@10.100.2.111 'ping -c 1 8.8.8.8'"
    fi
}

test_ssh_connectivity() {
    log INFO "Testing SSH connectivity..."
    
    local hosts=(
        "10.100.2.101:docker-host-01"
        "10.100.2.111:k8s-master-01"
        "10.100.2.121:k8s-worker-01"
    )
    
    for host_info in "${hosts[@]}"; do
        local host_ip="${host_info%:*}"
        local host_name="${host_info#*:}"
        
        run_test "SSH - $host_name accessible" \
            "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$host_ip 'echo ok'"
    done
}

test_docker_infrastructure() {
    log INFO "Testing Docker infrastructure..."
    
    if [[ "$QUICK_CHECK" == true ]]; then
        log INFO "Skipping Docker tests (quick check mode)"
        return
    fi
    
    local docker_host="10.100.2.101"
    
    run_test "Docker - Service running" \
        "ssh -o StrictHostKeyChecking=no ubuntu@$docker_host 'sudo systemctl is-active docker'"
    
    run_test "Docker - Version check" \
        "ssh -o StrictHostKeyChecking=no ubuntu@$docker_host 'docker --version'"
    
    run_test "Docker - Container engine functional" \
        "ssh -o StrictHostKeyChecking=no ubuntu@$docker_host 'docker run --rm hello-world'"
    
    run_test "Docker Compose - Installation check" \
        "ssh -o StrictHostKeyChecking=no ubuntu@$docker_host 'docker compose version'"
}

test_ansible_connectivity() {
    log INFO "Testing Ansible connectivity..."
    
    cd "$PROJECT_ROOT/ansible"
    
    run_test "Ansible - All hosts reachable" \
        "ansible all -m ping --one-line"
    
    run_test "Ansible - Inventory valid" \
        "ansible-inventory --list > /dev/null"
    
    cd - >/dev/null
}

test_terraform_state() {
    log INFO "Testing Terraform state..."
    
    cd "$PROJECT_ROOT/terraform"
    
    run_test "Terraform - State file exists" \
        "test -f terraform.tfstate"
    
    run_test "Terraform - State valid" \
        "terraform show > /dev/null"
    
    run_test "Terraform - Plan shows no changes" \
        "terraform plan -detailed-exitcode -var-file='environments/$ENVIRONMENT/terraform.tfvars'"
    
    cd - >/dev/null
}

test_security_configuration() {
    log INFO "Testing security configuration..."
    
    local hosts=("10.100.2.101" "10.100.2.111" "10.100.2.121")
    
    for host in "${hosts[@]}"; do
        run_test "Security - UFW firewall active on $host" \
            "ssh -o StrictHostKeyChecking=no ubuntu@$host 'sudo ufw status | grep -q \"Status: active\"'"
        
        run_test "Security - Fail2ban running on $host" \
            "ssh -o StrictHostKeyChecking=no ubuntu@$host 'sudo systemctl is-active fail2ban'"
    done
}

test_system_health() {
    log INFO "Testing system health..."
    
    local hosts=("10.100.2.101" "10.100.2.111" "10.100.2.121")
    
    for host in "${hosts[@]}"; do
        run_test "Health - System load acceptable on $host" \
            "ssh -o StrictHostKeyChecking=no ubuntu@$host 'test \$(cat /proc/loadavg | cut -d\" \" -f1 | cut -d\".\" -f1) -lt 5'"
        
        run_test "Health - Memory usage acceptable on $host" \
            "ssh -o StrictHostKeyChecking=no ubuntu@$host 'test \$(free | grep Mem: | awk \"{print int(\$3/\$2 * 100)}\") -lt 90'"
        
        run_test "Health - Disk space acceptable on $host" \
            "ssh -o StrictHostKeyChecking=no ubuntu@$host 'test \$(df / | tail -1 | awk \"{print \$5}\" | sed \"s/%//\") -lt 90'"
    done
}

generate_report() {
    log INFO "Generating validation report..."
    
    local report_file="$LOG_DIR/validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" <<EOF
Proxmox Infrastructure Validation Report
========================================

Environment: $ENVIRONMENT
Date: $(date)
Total Tests: $TESTS_TOTAL
Tests Passed: $TESTS_PASSED
Tests Failed: $TESTS_FAILED
Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%

Status: $([ $TESTS_FAILED -eq 0 ] && echo "HEALTHY" || echo "ISSUES DETECTED")

Detailed Results:
================
EOF
    
    cat "$LOG_FILE" >> "$report_file"
    
    log INFO "Report saved: $report_file"
}

print_summary() {
    echo ""
    echo -e "${BLUE}=================================${NC}"
    echo -e "${BLUE}Infrastructure Validation Summary${NC}"
    echo -e "${BLUE}=================================${NC}"
    echo -e "Environment: ${YELLOW}$ENVIRONMENT${NC}"
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "Status: ${GREEN}ALL TESTS PASSED${NC}"
        echo -e "Infrastructure is ${GREEN}HEALTHY${NC}"
    else
        echo -e "Status: ${RED}SOME TESTS FAILED${NC}"
        echo -e "Infrastructure has ${RED}ISSUES${NC}"
    fi
    
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Validate Proxmox infrastructure deployment.

OPTIONS:
    -e, --environment ENV    Set environment (dev/staging/prod) [default: dev]
    -q, --quick             Run quick validation (skip time-consuming tests)
    -v, --verbose           Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                     Run full validation
    $0 -q                  Run quick validation
    $0 -e prod -v          Run verbose validation for production

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
            -q|--quick)
                QUICK_CHECK=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Setup logging
    mkdir -p "$LOG_DIR"
    
    log INFO "Starting infrastructure validation"
    log INFO "Environment: $ENVIRONMENT"
    log INFO "Quick check: $QUICK_CHECK"
    
    # Run validation tests
    test_proxmox_api
    test_sdn_configuration
    test_management_container
    test_vm_templates
    test_infrastructure_vms
    test_network_connectivity
    test_ssh_connectivity
    test_docker_infrastructure
    test_ansible_connectivity
    test_terraform_state
    test_security_configuration
    test_system_health
    
    # Generate report
    generate_report
    print_summary
    
    # Exit with appropriate code
    exit $TESTS_FAILED
}

# Handle script interruption
trap 'log ERROR "Validation interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"