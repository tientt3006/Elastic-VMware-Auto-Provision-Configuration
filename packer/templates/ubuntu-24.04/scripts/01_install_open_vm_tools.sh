#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: 01_install_open_vm_tools.sh
# Purpose: Verify, configure and enable open-vm-tools service for VMware vSphere
# ==============================================================================

echo "==> Configuring open-vm-tools..."

# open-vm-tools is pre-installed on the Ubuntu 24.04 Live Server ISO.
# Skip apt-get update/install to avoid DNS timeout stalls in air-gapped environments.
if dpkg -l open-vm-tools &>/dev/null; then
  echo "==> open-vm-tools already installed, skipping apt-get."
else
  echo "==> open-vm-tools not found, attempting install..."
  apt-get update -y || true
  apt-get install -y --no-install-recommends open-vm-tools || true
fi

# Enable and start services
systemctl enable open-vm-tools.service || true
systemctl restart open-vm-tools.service || true


# Configure VMware tools guestinfo parameters
mkdir -p /etc/vmware-tools
cat << 'EOF' > /etc/vmware-tools/tools.conf
[guestinfo]

[logging]
log = true
vmsvc.level = warning
vmsvc.handler = syslog

[powerops]
poweron-script = /etc/vmware-tools/poweron-vm-default
poweroff-script = /etc/vmware-tools/poweroff-vm-default
reboot-script = /etc/vmware-tools/reboot-vm-default
resume-script = /etc/vmware-tools/resume-vm-default
suspend-script = /etc/vmware-tools/suspend-vm-default
EOF

echo "==> open-vm-tools successfully configured."
