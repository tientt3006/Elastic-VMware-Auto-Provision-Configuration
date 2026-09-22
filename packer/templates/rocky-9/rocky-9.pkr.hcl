# ==============================================================================
# Automated Rocky Linux 9 Minimal Golden Image Template Pipeline for VMware vSphere
# Builds hardened, Perl & GOSC ready template with open-vm-tools preinstalled
# ==============================================================================

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    vsphere = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}

locals {
  kickstart = <<-KS
    #version=RHEL9
    cdrom
    repo --name="AppStream" --baseurl="https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/" --noverifyssl
    repo --name="BaseOS" --baseurl="https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/" --noverifyssl
    text
    eula --agreed
    lang en_US.UTF-8
    keyboard us
    timezone UTC --utc
    network --bootproto=dhcp --device=link --activate
    rootpw --lock
    user --name=${var.ssh_username} --groups=wheel --iscrypted --password=${var.ssh_password_hash}
    firewall --enabled --ssh
    selinux --enforcing
    bootloader --location=mbr --append="console=tty0"
    zerombr
    clearpart --all --initlabel
    autopart --type=lvm
    services --enabled=NetworkManager,sshd
    skipx
    reboot --eject

    %packages --ignoremissing --excludedocs
    @core
    sudo
    firewalld
    audit
    rsyslog
    openssh-server
    open-vm-tools
    perl
    NetworkManager-initscripts-updown
    chrony
    ca-certificates
    curl
    bind-utils
    iproute
    lsof
    pciutils
    tar
    unzip
    vim-minimal
    %{for package in var.additional_packages~}
    ${package}
    %{endfor~}
    %end

    %post --nochroot --log=/mnt/sysimage/root/ks-post-nochroot.log
    # Copy DNS configuration into target chroot so dnf works
    cp -L /etc/resolv.conf /mnt/sysimage/etc/resolv.conf 2>/dev/null || true
    %end

    %post --log=/root/ks-post.log
    if ! rpm -q open-vm-tools >/dev/null 2>&1; then
      dnf -y install open-vm-tools perl || true
    fi
    echo "${var.ssh_username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${var.ssh_username}
    chmod 0440 /etc/sudoers.d/${var.ssh_username}

    systemctl enable vmtoolsd.service || true
    systemctl enable chronyd.service || true
    systemctl enable firewalld.service || true
    systemctl enable auditd.service || true
    systemctl enable rsyslog.service || true

    if [ -n "${var.ssh_public_key}" ]; then
      install -d -m 0700 -o ${var.ssh_username} -g ${var.ssh_username} /home/${var.ssh_username}/.ssh
      printf '%s\n' '${var.ssh_public_key}' > /home/${var.ssh_username}/.ssh/authorized_keys
      chown ${var.ssh_username}:${var.ssh_username} /home/${var.ssh_username}/.ssh/authorized_keys
      chmod 0600 /home/${var.ssh_username}/.ssh/authorized_keys
    fi
    %end
  KS
}

source "vsphere-iso" "rocky" {
  # vCenter connection configuration
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_user
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure_connection

  # Infrastructure placement
  datacenter                     = var.vcenter_datacenter
  cluster                        = var.vcenter_cluster
  resource_pool                  = var.vcenter_resource_pool
  datastore                      = var.vcenter_datastore
  folder                         = var.vcenter_folder
  set_host_for_datastore_uploads = true

  # Virtual machine identity and lifecycle
  vm_name             = var.vm_name
  convert_to_template = true

  # Hardware specifications
  guest_os_type        = "rhel9_64Guest"
  firmware             = "efi"
  CPUs                 = var.vm_cpu_cores
  RAM                  = var.vm_mem_size
  disk_controller_type = ["pvscsi"]
  storage {
    disk_size             = var.vm_disk_size
    disk_thin_provisioned = var.vm_disk_thin
  }

  # Virtual networking
  network_adapters {
    network      = var.vcenter_network
    network_card = "vmxnet3"
  }
  vm_version           = 19
  remove_cdrom         = true
  tools_upgrade_policy = true

  # Content Library / Datastore ISO image source
  iso_paths  = var.iso_paths
  cd_content = { "/ks.cfg" = local.kickstart }
  cd_label   = "KS"

  # EFI boot command sequence for Rocky Linux 9 Anaconda
  # boot_wait of 8s: EFI GRUB requires additional probe time vs BIOS.
  # inst.ks=hd:LABEL=KS: targets the Packer-generated ISO explicitly,
  # avoiding ambiguity with the installer ISO when two optical drives are present.
  boot_order = var.boot_order
  boot_wait  = "8s"
  boot_command = [
    "<up><wait>",
    "e<wait>",
    "<down><down><end><wait>",
    " inst.ks=hd:LABEL=KS:/ks.cfg inst.text",
    "<enter><wait>",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]

  ip_wait_timeout   = "30m"
  ip_settle_timeout = "10s"

  # SSH communicator setup
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = var.ssh_timeout

  # Graceful guest shutdown
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  shutdown_timeout = "10m"
}

build {
  sources = ["source.vsphere-iso.rocky"]

  provisioner "shell" {
    environment_vars = [
      "BUILD_USERNAME=${var.ssh_username}",
      "BUILD_SSH_PUBLIC_KEY=${var.ssh_public_key}"
    ]
    script = "${path.root}/scripts/01_harden_rocky.sh"
  }

  provisioner "shell" {
    inline = [
      "rpm -q open-vm-tools",
      "sudo systemctl enable --now vmtoolsd.service",
      "sudo systemctl is-active --quiet vmtoolsd.service",
      "sudo dnf -y install NetworkManager-initscripts-updown perl || true",
      "sudo mkdir -p /etc/sysconfig/network-scripts",
      "sudo chmod 0755 /etc/sysconfig/network-scripts",
      "sudo install -d -m 0755 /etc/vmware-tools",
      "printf '[customization]\\nenable-custom-scripts = true\\n' | sudo tee /etc/vmware-tools/tools.conf",
      "sudo dnf -y update",
      "sudo systemctl enable --now chronyd.service",
      "sudo truncate -s 0 /etc/machine-id",
      "if [ -d /var/lib/dbus ]; then sudo rm -f /var/lib/dbus/machine-id && sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id; fi",
      "sudo cloud-init clean --logs 2>/dev/null || true",
      "sudo rm -f /root/.ssh/authorized_keys",
      "history -c || true"
    ]
  }
}
