#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: 03_configure_ufw.sh
# Purpose: Configure Uncomplicated Firewall (UFW) baseline policies
# ==============================================================================

echo "==> Configuring UFW firewall policies..."

if command -v ufw >/dev/null 2>&1; then
  # Set default policies: reject/deny incoming, allow outgoing
  ufw --force default deny incoming
  ufw --force default allow outgoing

  # Allow standard administrative SSH traffic
  ufw allow 22/tcp comment 'Administrative SSH'

  # Enable firewall service non-interactively
  ufw --force enable

  systemctl enable ufw.service
  echo "==> UFW firewall policies configured and enabled."
else
  echo "==> UFW not present, skipping firewall configuration."
fi
