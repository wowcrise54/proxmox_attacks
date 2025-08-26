# Quick Setup Guide

This guide will help you deploy the Proxmox infrastructure automation solution from scratch.

## Prerequisites Checklist

- [ ] Proxmox VE 8.0+ installed and accessible
- [ ] Minimum 32GB RAM, 500GB storage available
- [ ] Network connectivity and internet access
- [ ] API access enabled on Proxmox
- [ ] Linux/WSL environment for running scripts

## Step 1: Proxmox API Setup

1. **Create API Token in Proxmox Web UI:**
   - Go to Datacenter > Permissions > API Tokens
   - Add new token: `infrastructure@pve!automation`
   - Note down the Token ID and Secret

2. **Set Environment Variables:**
```bash
export PROXMOX_API_URL=\"https://YOUR_PROXMOX_IP:8006/api2/json\"
export PROXMOX_API_TOKEN_ID=\"infrastructure@pve!automation\"
export PROXMOX_API_TOKEN_SECRET=\"your-secret-here\"
```

## Step 2: Download Ubuntu ISO

1. **Download Ubuntu 22.04 Server ISO:**
```bash
cd /var/lib/vz/template/iso/
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso
```

## Step 3: Clone and Setup Project

```bash
git clone <your-repo-url>
cd proxmox_attacks

# Make scripts executable
chmod +x bootstrap/*.sh scripts/*.sh

# Create logs directory
mkdir -p logs
```

## Step 4: Bootstrap Proxmox (Run on Proxmox Host)

```bash
# Copy bootstrap script to Proxmox host
scp bootstrap/install-proxmox.sh root@YOUR_PROXMOX_IP:/tmp/

# SSH to Proxmox host and run
ssh root@YOUR_PROXMOX_IP
cd /tmp
./install-proxmox.sh
```

**What this does:**
- Configures SDN networking
- Creates management container with automation tools
- Sets up firewall and routing

## Step 5: Deploy Infrastructure

```bash
# From your local machine
./scripts/deploy.sh --environment dev
```

**Deployment phases:**
1. Builds VM templates with Packer (15-30 minutes)
2. Provisions infrastructure with Terraform (5-10 minutes)
3. Configures systems with Ansible (10-15 minutes)

## Step 6: Validate Deployment

```bash
# Run validation tests
./scripts/validate.sh

# Should show all tests passed
```

## Step 7: Access Your Infrastructure

```bash
# Access management container
pct enter 100

# SSH to VMs
ssh ubuntu@10.100.2.101  # Docker host
ssh ubuntu@10.100.2.111  # K8s master
ssh ubuntu@10.100.2.121  # K8s worker
```

## Troubleshooting

### Common Issues

1. **API Connection Failed**
   - Check API URL and credentials
   - Verify network connectivity
   - Check firewall rules

2. **Template Build Failed**
   - Verify ISO file exists and is accessible
   - Check Proxmox storage permissions
   - Review packer logs

3. **Network Issues**
   - Check SDN configuration in Proxmox UI
   - Verify bridge configuration
   - Check DHCP service status

4. **SSH Connection Failed**
   - Verify VM is running: `qm status <vmid>`
   - Check cloud-init logs in VM
   - Verify SSH keys configuration

### Log Files

- Bootstrap: Check output during execution
- Deployment: `logs/deployment-*.log`
- Validation: `logs/validation-*.log`
- Packer: Build output and error messages
- Terraform: `terraform/terraform.log`
- Ansible: `ansible/ansible.log`

## Next Steps

1. **Customize Configuration:**
   - Edit `terraform/environments/dev/terraform.tfvars`
   - Modify VM specifications and network settings
   - Add your SSH keys

2. **Add More Infrastructure:**
   - Create additional VM configurations
   - Extend Ansible playbooks
   - Build custom Packer templates

3. **Production Deployment:**
   - Review production configuration
   - Set up monitoring and backups
   - Configure high availability

## Support

If you encounter issues:

1. Check the troubleshooting section in README.md
2. Review log files for error messages
3. Verify all prerequisites are met
4. Test each component individually

## Success Indicators

✅ **Successful deployment includes:**
- Management container running and accessible
- All VMs provisioned and running
- Network connectivity between all components
- SSH access to all VMs
- All validation tests passing

🎉 **Congratulations! Your Proxmox infrastructure is ready for use.**