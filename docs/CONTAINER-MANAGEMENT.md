# Container Management Guide

This guide explains how to use the management container scripts for Proxmox infrastructure automation.

## 📋 Overview

The management container is the central control point for your Proxmox infrastructure. It contains all automation tools (Terraform, Packer, Ansible) and manages your entire infrastructure deployment.

## 🛠️ Available Scripts

### 1. Bootstrap Scripts

#### `bootstrap/setup-management-container.sh`
**Purpose**: Configure an existing container with all automation tools

**Usage**:
```bash
# Run inside a container or via pct exec
./bootstrap/setup-management-container.sh
```

**What it does**:
- Updates system packages
- Creates infrastructure user with sudo access
- Installs Terraform, Packer, Ansible
- Installs Proxmox API tools and additional utilities
- Sets up workspace directory `/opt/infrastructure`
- Configures environment and creates management scripts

#### `bootstrap/configure-remote-container.sh`
**Purpose**: Remotely configure an existing LXC container

**Usage**:
```bash
# Run on Proxmox host
./bootstrap/configure-remote-container.sh [CONTAINER_ID]
```

**What it does**:
- Copies setup script to target container
- Executes container setup remotely
- Copies project files to container workspace
- Creates environment variables template
- Validates installation

### 2. Container Management

#### `scripts/container-manage.sh`
**Purpose**: Complete container lifecycle management

**Usage**:
```bash
# Container operations
./scripts/container-manage.sh status           # Show detailed status
./scripts/container-manage.sh start            # Start container
./scripts/container-manage.sh stop             # Stop container
./scripts/container-manage.sh restart          # Restart container

# Access container
./scripts/container-manage.sh enter            # Enter as root
./scripts/container-manage.sh shell            # Enter as infrastructure user

# Execute commands
./scripts/container-manage.sh exec "command"   # Run command in container

# Maintenance
./scripts/container-manage.sh logs             # Show logs
./scripts/container-manage.sh backup          # Create backup
./scripts/container-manage.sh clone 101       # Clone to new container
```

## 🚀 Setup Workflows

### Scenario 1: Fresh Container Setup

1. **Create LXC container in Proxmox UI**
2. **Configure remotely from Proxmox host**:
   ```bash
   ./bootstrap/configure-remote-container.sh 100
   ```
3. **Access and configure**:
   ```bash
   ./scripts/container-manage.sh shell
   cd /opt/infrastructure
   cp .env.template .env
   nano .env  # Configure API credentials
   source .env
   ```

### Scenario 2: Manual Container Setup

1. **Access existing container**:
   ```bash
   pct enter 100
   ```
2. **Run setup script**:
   ```bash
   # Copy setup script to container first
   ./bootstrap/setup-management-container.sh
   ```
3. **Copy project files manually** or use git clone

### Scenario 3: Automated Integration

Include in your main bootstrap script:
```bash
# In bootstrap/install-proxmox.sh
# After container creation:
./bootstrap/configure-remote-container.sh $MANAGEMENT_CONTAINER_ID
```

## 🔧 Container Components

### Installed Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **Terraform** | ~1.6.6 | Infrastructure provisioning |
| **Packer** | ~1.9.4 | VM template building |
| **Ansible** | ~8.0.0 | Configuration management |
| **Docker CLI** | Latest | Remote Docker management |
| **kubectl** | Latest | Kubernetes management |
| **Helm** | Latest | Kubernetes package management |

### Users and Permissions

- **root**: System administration
- **infrastructure**: Automation tasks (passwordless sudo)

### Directory Structure

```
/opt/infrastructure/           # Main workspace
├── terraform/                 # Infrastructure code
├── ansible/                  # Configuration management
├── packer/                   # Template building
├── scripts/                  # Management scripts
├── logs/                     # Operation logs
├── .env.template             # Environment template
└── .env                      # Your configuration (create this)
```

### Environment Configuration

Create `/opt/infrastructure/.env`:
```bash
# Required
export PROXMOX_API_URL="https://your-proxmox:8006/api2/json"
export PROXMOX_API_TOKEN_ID="your-token-id"  
export PROXMOX_API_TOKEN_SECRET="your-secret"

# Optional
export PROXMOX_NODE="pve"
export TF_VAR_environment="dev"
```

## 📊 Container Monitoring

### Status Checking

```bash
# Comprehensive status
./scripts/container-manage.sh status

# Quick status
pct status 100

# Resource usage
pct exec 100 -- htop

# Infrastructure status
pct exec 100 -- infra-status
```

### Log Management

```bash
# Container system logs
./scripts/container-manage.sh logs

# Infrastructure logs
pct exec 100 -- tail -f /opt/infrastructure/logs/*.log

# Specific tool logs
pct exec 100 -- tail -f /opt/infrastructure/logs/terraform.log
```

## 🔄 Container Operations

### Backup and Recovery

```bash
# Create backup
./scripts/container-manage.sh backup local stop

# Manual backup with vzdump
vzdump 100 --storage local --mode stop --compress gzip

# Restore from backup
pct restore 101 local:backup-file.tar.gz --storage local-lvm
```

### Cloning and Testing

```bash
# Clone for testing
./scripts/container-manage.sh clone 101 "test-environment"

# Configure clone
./bootstrap/configure-remote-container.sh 101
```

### Updates and Maintenance

```bash
# Update container tools
pct exec 100 -- /bootstrap/setup-management-container.sh

# Update system packages
pct exec 100 -- apt update && apt upgrade -y

# Update infrastructure code
pct exec 100 -- bash -c "cd /opt/infrastructure && git pull"
```

## 🛡️ Security Considerations

### Access Control
- Use API tokens instead of passwords
- Limit container network access if needed
- Regular security updates

### Secrets Management
- Store `.env` file securely
- Use proper file permissions (600)
- Consider using external secret management

### Network Security
- Container runs in isolated SDN
- Firewall rules control access
- Monitor container access logs

## 🐛 Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check configuration
pct config 100

# Check system logs
journalctl -u pve-container@100

# Try manual start
pct start 100 --debug
```

#### Tools Not Working
```bash
# Re-run setup
pct exec 100 -- /bootstrap/setup-management-container.sh

# Check tool versions
pct exec 100 -- terraform version
pct exec 100 -- packer version
pct exec 100 -- ansible --version
```

#### Network Issues
```bash
# Test connectivity
pct exec 100 -- ping 8.8.8.8

# Check interface
pct exec 100 -- ip addr show

# Restart networking
pct restart 100
```

#### Permission Issues
```bash
# Fix workspace permissions
pct exec 100 -- chown -R infrastructure:infrastructure /opt/infrastructure

# Fix sudo configuration
pct exec 100 -- visudo /etc/sudoers.d/99-infrastructure
```

### Log Analysis

#### Infrastructure Deployment Issues
```bash
# Check deployment logs
pct exec 100 -- tail -100 /opt/infrastructure/logs/deployment-*.log

# Check Terraform logs
pct exec 100 -- tail -100 /opt/infrastructure/logs/terraform.log

# Check Ansible logs  
pct exec 100 -- tail -100 /opt/infrastructure/logs/ansible.log
```

#### Performance Issues
```bash
# Check resource usage
pct exec 100 -- top
pct exec 100 -- df -h
pct exec 100 -- free -h

# Check I/O
pct exec 100 -- iotop
```

## 🔗 Integration with Main Deployment

The container management scripts integrate seamlessly with the main deployment process:

1. **Bootstrap Phase**: `install-proxmox.sh` creates and configures container
2. **Setup Phase**: `configure-remote-container.sh` installs tools and copies files  
3. **Deploy Phase**: `deploy.sh` uses container to orchestrate infrastructure
4. **Validate Phase**: `validate.sh` tests container and infrastructure
5. **Manage Phase**: `container-manage.sh` provides ongoing management

## 📚 Reference

### Environment Variables
- `CONTAINER_ID`: Target container ID (default: 100)
- `PROXMOX_API_*`: Proxmox connection settings
- `TF_VAR_*`: Terraform variables
- `ANSIBLE_*`: Ansible configuration

### File Locations
- Setup scripts: `bootstrap/`
- Management scripts: `scripts/`
- Container workspace: `/opt/infrastructure`
- Container logs: `/var/log/`, `/opt/infrastructure/logs/`
- Environment config: `/opt/infrastructure/.env`

### Useful Commands
```bash
# Quick container access
export CONTAINER_ID=100
./scripts/container-manage.sh shell

# Infrastructure management
pct exec 100 -- infra-manage status
pct exec 100 -- infra-manage deploy
pct exec 100 -- infra-manage validate

# File operations
pct push 100 localfile /opt/infrastructure/remotefile
pct pull 100 /opt/infrastructure/remotefile localfile
```

This container management system provides a robust, scalable foundation for infrastructure automation with Proxmox VE.