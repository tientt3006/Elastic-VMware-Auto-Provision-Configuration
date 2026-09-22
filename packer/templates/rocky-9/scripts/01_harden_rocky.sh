#!/usr/bin/env bash
# ==============================================================================
# OS Baseline Hardening and VMware GOSC Customization for Rocky Linux 9
# ==============================================================================
set -euo pipefail

# 1. Cấu hình SSH Server bảo mật
install -d -m 0755 /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/10-image-baseline.conf <<'EOF'
PermitRootLogin no
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

if [[ -n "${BUILD_SSH_PUBLIC_KEY:-}" ]]; then
  cat >> /etc/ssh/sshd_config.d/10-image-baseline.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
fi

# 2. Thiết lập thông số bảo mật nhân Linux (Kernel Sysctl)
cat > /etc/sysctl.d/60-image-baseline.conf <<'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
EOF

sysctl --system >/dev/null

# 3. Tiêm SSH Public Key nếu có
if [[ -n "${BUILD_SSH_PUBLIC_KEY:-}" ]]; then
  install -d -m 0700 -o "${BUILD_USERNAME}" -g "${BUILD_USERNAME}" "/home/${BUILD_USERNAME}/.ssh"
  printf '%s\n' "${BUILD_SSH_PUBLIC_KEY}" > "/home/${BUILD_USERNAME}/.ssh/authorized_keys"
  chown "${BUILD_USERNAME}:${BUILD_USERNAME}" "/home/${BUILD_USERNAME}/.ssh/authorized_keys"
  chmod 0600 "/home/${BUILD_USERNAME}/.ssh/authorized_keys"
fi

# 4. Kích hoạt Customization Script cho VMware Tools
install -d -m 0755 /etc/vmware-tools
cat > /etc/vmware-tools/tools.conf <<'EOF'
[customization]
enable-custom-scripts = true
EOF

# Đảm bảo thư mục network-scripts tồn tại cho VMware Guest OS Customization (toolsDeployPkg)
install -d -m 0755 /etc/sysconfig/network-scripts

dnf install -y NetworkManager-initscripts-updown perl || true

sshd -t
systemctl enable --now firewalld auditd rsyslog chronyd vmtoolsd
systemctl reload sshd

# 5. Dọn dẹp Machine ID để chuẩn bị nhân bản (Clone Generalization)
truncate -s 0 /etc/machine-id
if [[ -d /var/lib/dbus ]]; then
  rm -f /var/lib/dbus/machine-id
  ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

# Xóa dấu vết cài đặt và dọn dẹp log trước khi chuyển đổi sang Template
rm -f /root/ks-post.log /root/anaconda-ks.cfg
rm -rf /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} \;
