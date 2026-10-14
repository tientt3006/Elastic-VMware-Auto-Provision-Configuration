#!/usr/bin/env bash
# ==============================================================================
# Script: 01_setup_vmtools.sh
# Purpose: Configure VMware Tools, Guest OS Customization (GOSC) and System Base
# ==============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "[*] Verifying open-vm-tools and GOSC prerequisites..."

# 1. Ensure open-vm-tools and perl are present (required for vSphere Linux GOSC)
if ! rpm -q open-vm-tools >/dev/null 2>&1; then
  echo "    Installing open-vm-tools..."
  dnf install -y open-vm-tools
fi

if ! rpm -q perl >/dev/null 2>&1; then
  echo "    Installing perl..."
  dnf install -y perl
fi

# 2. Configure VMware Tools Custom Scripts
install -d -m 0755 /etc/vmware-tools
cat > /etc/vmware-tools/tools.conf << 'EOF'
[customization]
enable-custom-scripts = true

[guestinfo]
primary-nics = ens192,ens224,ens33,eth0
EOF

# 3. Ensure legacy network-scripts directory exists for toolsDeployPkg
install -d -m 0755 /etc/sysconfig/network-scripts
dnf install -y NetworkManager-initscripts-updown || true

# 4. Enable and start core services
systemctl enable --now vmtoolsd.service
systemctl enable --now chronyd.service
systemctl enable --now sshd.service

# 5. Linux Kernel Network Security Baseline
cat > /etc/sysctl.d/99-vm-baseline.conf << 'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
EOF
sysctl --system >/dev/null 2>&1 || true

echo "[+] 01_setup_vmtools.sh completed successfully."
