#!/usr/bin/env bash
# ==============================================================================
# Script: 02_clean_template.sh
# Purpose: Deep Template Generalization and Artifact Sanitization
# Prepares Oracle Linux 9 for seamless cloning under VMware vSphere
# ==============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "[*] Initiating Golden Template Generalization and Cleanup..."

# 1. Stop Logging Daemons during cleanup
systemctl stop rsyslog 2>/dev/null || true
systemctl stop auditd 2>/dev/null || true

# 2. Reset Machine ID (Enforces unique ID generation on every cloned instance boot)
echo "    Truncating /etc/machine-id..."
truncate -s 0 /etc/machine-id
if [[ -d /var/lib/dbus ]]; then
  rm -f /var/lib/dbus/machine-id
  ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

# 3. Wipe SSH Host Keys (Forces sshd-keygen to regenerate unique keys per clone)
echo "    Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# 4. Remove Persistent Network & Udev Rules
echo "    Cleaning udev and NetworkManager device bindings..."
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true
rm -f /etc/udev/rules.d/80-net-setup-link.rules 2>/dev/null || true

# Strip persistent MAC and UUID from NetworkManager connection profiles
if [[ -d /etc/NetworkManager/system-connections ]]; then
  for conn in /etc/NetworkManager/system-connections/*; do
    if [[ -f "$conn" ]]; then
      sed -i '/^uuid=/d' "$conn" 2>/dev/null || true
      sed -i '/^mac-address=/d' "$conn" 2>/dev/null || true
      sed -i '/^cloned-mac-address=/d' "$conn" 2>/dev/null || true
    fi
  done
fi

# 5. Clean Package Manager Caches
echo "    Cleaning DNF repository metadata and cache..."
dnf clean all
rm -rf /var/cache/dnf /var/cache/yum

# 6. Sanitize Log Files and Audit Logs
echo "    Truncating system log files..."
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -f /var/log/*.gz /var/log/*.[0-9] /var/log/*-[0-9]* 2>/dev/null || true

# Remove installer-specific logs
rm -f /root/anaconda-ks.cfg /root/original-ks.cfg /root/ks-post.log /root/ks-post-nochroot.log

# 7. Wipe Temporary Directories
echo "    Purging temporary directories..."
rm -rf /tmp/* /var/tmp/* /tmp/.[!.]* /var/tmp/.[!.]* 2>/dev/null || true

# 8. Clean Shell Histories
echo "    Clearing bash histories..."
rm -f /root/.bash_history
find /home -name ".bash_history" -exec rm -f {} \; 2>/dev/null || true
history -c || true

# 9. Sync filesystem buffers to disk
sync

echo "[+] Golden Template Generalization completed successfully."
