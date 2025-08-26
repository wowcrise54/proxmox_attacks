# Proxmox SDN Configuration Troubleshooting Guide

## Issue Fixed: "Unknown option: options" Error

### Problem
The script was failing with the error:
```
Unknown option: options
400 unable to parse option
pvesh set <api_path> [OPTIONS] [FORMAT_OPTIONS]
```

### Root Cause
The script was using incorrect syntax for enabling SDN:
```bash
pvesh set /cluster/sdn --options "enable=1"  # INCORRECT
```

### Solution
Use the correct parameter syntax:
```bash
pvesh set /cluster/sdn --enable 1  # CORRECT
```

## Changes Made

### 1. Fixed SDN Enable Command
**Before:**
```bash
pvesh set /cluster/sdn --options "enable=1"
```

**After:**
```bash
pvesh set /cluster/sdn --enable 1
```

### 2. Added Required SDN Package
**Before:**
```bash
apt-get install -y \
    bridge-utils \
    ifupdown2 \
    # ... other packages
```

**After:**
```bash
apt-get install -y \
    bridge-utils \
    ifupdown2 \
    # ... other packages
    libpve-network-perl  # Required for SDN functionality
```

### 3. Improved Error Handling
Added better checking for SDN status before attempting to enable it:
```bash
# Check if SDN is already enabled
if pvesh get /cluster/sdn/status >/dev/null 2>&1; then
    info "SDN is already configured"
else
    info "Enabling SDN..."
    pvesh set /cluster/sdn --enable 1
    sleep 3
fi
```

## Common SDN Issues and Solutions

### 1. SDN Not Available
**Error:** `command not found` or SDN-related commands fail
**Solution:** Install the required package:
```bash
apt-get update
apt-get install libpve-network-perl
```

### 2. Bridge Not Found
**Error:** Bridge vmbr1 not found
**Solution:** Check available bridges:
```bash
ip link show
# or
pvesh get /nodes/$(hostname)/network
```

### 3. SDN Apply Issues
**Error:** SDN configuration fails to apply
**Solution:** 
```bash
# Check SDN status
pvesh get /cluster/sdn/status

# Reload network configuration
systemctl reload-or-restart networking
systemctl reload-or-restart frr
```

### 4. VNET Creation Failures
**Error:** Cannot create VNET
**Solution:** Ensure the zone exists first:
```bash
# List existing zones
pvesh get /cluster/sdn/zones

# Create zone if missing
pvesh create /cluster/sdn/zones \
    --zoneid "your-zone-name" \
    --type simple \
    --bridge vmbr1
```

## Verification Commands

### Check SDN Status
```bash
pvesh get /cluster/sdn/status
```

### List SDN Zones
```bash
pvesh get /cluster/sdn/zones
```

### List VNETs
```bash
pvesh get /cluster/sdn/vnets
```

### List Subnets for a VNET
```bash
pvesh get /cluster/sdn/vnets/VNET_NAME/subnets
```

### Apply SDN Configuration
```bash
pvesh set /cluster/sdn --apply 1
```

## Best Practices

1. **Always check if resources exist before creating them**
2. **Install required packages before configuring SDN**
3. **Use proper parameter syntax (--parameter value, not --options "parameter=value")**
4. **Add delays after major configuration changes**
5. **Validate configuration after applying changes**

## Useful Resources

- [Proxmox SDN Documentation](https://pve.proxmox.com/wiki/Software-Defined_Network)
- [Proxmox API Viewer](https://pve.proxmox.com/pve-docs/api-viewer/#/cluster/sdn)
- [Proxmox Community Forum](https://forum.proxmox.com/)