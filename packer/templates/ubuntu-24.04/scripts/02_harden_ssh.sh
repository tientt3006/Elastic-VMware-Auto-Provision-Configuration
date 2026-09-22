#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: 02_harden_ssh.sh
# Purpose: Apply OpenSSH server security baseline configuration
# ==============================================================================

echo "==> Applying OpenSSH server security baseline..."

mkdir -p /etc/ssh/sshd_config.d

cat << 'EOF' > /etc/ssh/sshd_config.d/99-hardening.conf
# Enterprise baseline SSH configuration
PermitRootLogin no
MaxAuthTries 4
PasswordAuthentication yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Ensure ssh host key regeneration service on initial boot
systemctl enable ssh.service

echo "==> OpenSSH security baseline applied."
