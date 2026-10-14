# ==============================================================================
# Unattended Kickstart Installation Profile for Oracle Linux 9
# Optimized for VMware vSphere Native Guest OS Customization (GOSC)
# ==============================================================================

# Installation source and UI mode
cdrom
text
eula --agreed

# Localization
lang en_US.UTF-8
keyboard us
timezone Asia/Ho_Chi_Minh --utc

# Dynamic Network Configuration during installation
network --bootproto=dhcp --device=link --activate --nameserver=8.8.8.8,1.1.1.1

# Security and User Accounts
rootpw --lock
user --name=${ssh_username} --groups=wheel --iscrypted --password=${ssh_password_hash}

# Firewall and Security Baseline
firewall --enabled --ssh
authselect select sssd
selinux --enforcing

# Storage and Partitioning (LVM)
zerombr
clearpart --all --initlabel
autopart --type=lvm

# Services Management
services --enabled=NetworkManager,sshd,vmtoolsd,chronyd

# Disable Graphical Environment
skipx

# Package Manifest
%packages --ignoremissing --excludedocs
@core
-iwl*firmware
sudo
open-vm-tools
perl
NetworkManager-initscripts-updown
chrony
ca-certificates
curl
bind-utils
iproute
lsof
tar
unzip
vim-minimal
rsyslog
audit
firewalld
%end

# Post-Installation System Configuration
%post --log=/root/ks-post.log
set -x

# 1. Passwordless Sudo for Template User
echo "${ssh_username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${ssh_username}
chmod 0440 /etc/sudoers.d/${ssh_username}
sed -i "s/^.*requiretty/#Defaults requiretty/" /etc/sudoers 2>/dev/null || true

# 2. VMware Tools Guest Customization Prerequisites
mkdir -p /etc/vmware-tools
cat << 'EOF' > /etc/vmware-tools/tools.conf
[customization]
enable-custom-scripts = true
EOF

# Ensure legacy network-scripts directory exists for vSphere toolsDeployPkg engine
mkdir -p /etc/sysconfig/network-scripts
chmod 0755 /etc/sysconfig/network-scripts

# 3. Enable System Services
systemctl enable vmtoolsd.service || true
systemctl enable chronyd.service || true
systemctl enable sshd.service || true
systemctl enable firewalld.service || true

# 4. Optional SSH Public Key Injection
if [ -n "${ssh_public_key}" ]; then
  install -d -m 0700 -o ${ssh_username} -g ${ssh_username} /home/${ssh_username}/.ssh
  printf '%s\n' '${ssh_public_key}' > /home/${ssh_username}/.ssh/authorized_keys
  chown ${ssh_username}:${ssh_username} /home/${ssh_username}/.ssh/authorized_keys
  chmod 0600 /home/${ssh_username}/.ssh/authorized_keys
fi

%end

# Finalize and reboot
reboot --eject
