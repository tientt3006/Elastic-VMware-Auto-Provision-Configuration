#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: 04_generalize_template.sh
# Purpose: Deep OS sanitization, machine-id reset, and cloud-init preparation
#          Ensures template is fully generalized for Terraform automation.
# ==============================================================================

echo "==> Preparing cloud-init for VMware vSphere customization..."

# Configure Cloud-Init datasources to support VMware guest customization
mkdir -p /etc/cloud/cloud.cfg.d

cat << 'EOF' > /etc/cloud/cloud.cfg.d/99-vmware-datasources.cfg
datasource_list: [ VMware, NoCloud, None ]
EOF

# Disable cloud-init network management to allow Terraform netplan customization
cat << 'EOF' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF

# Clean cloud-init artifacts
cloud-init clean --logs --seed

echo "==> Configuring SSH host key regeneration on first boot..."
# Remove persistent SSH host keys
rm -f /etc/ssh/ssh_host_*

# Create a systemd one-shot service to regenerate SSH host keys if not generated
cat << 'EOF' > /etc/systemd/system/regenerate-ssh-host-keys.service
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionFileNotEmpty=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable regenerate-ssh-host-keys.service

echo "==> Truncating machine-id to ensure unique DHCP lease allocation..."
# Truncate machine-id
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

echo "==> Sanitizing temporary files, package caches and logs..."
# Clean APT cache
apt-get clean -y
apt-get autoremove -y
rm -rf /var/lib/apt/lists/*

# Truncate all log files
find /var/log -type f -exec truncate -s 0 {} +

# Clean persistent udev network rules, DHCP leases and installer netplan
rm -rf /var/lib/dhcp/* /var/lib/dhcpcd/* /var/lib/NetworkManager/*
rm -f /etc/netplan/*.yaml
rm -rf /tmp/* /var/tmp/*

# Clear shell history
truncate -s 0 ~/.bash_history /root/.bash_history || true
history -c || true

echo "==> Golden template generalization complete."
