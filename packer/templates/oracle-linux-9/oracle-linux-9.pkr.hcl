# ==============================================================================
# Automated Oracle Linux 9 Golden Template Pipeline for VMware vSphere
# Fully automated Kickstart installation with open-vm-tools, GOSC readiness,
# and complete template sanitization for Enterprise Linux 9 workloads.
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
  kickstart_content = templatefile("${path.root}/data/ks.pkrtpl.hcl", {
    ssh_username      = var.ssh_username
    ssh_password_hash = var.ssh_password_hash
    ssh_public_key    = var.ssh_public_key
  })
}

source "vsphere-iso" "oracle9" {
  # vCenter connection configuration
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_user
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure_connection

  # Infrastructure placement
  datacenter                     = var.vcenter_datacenter
  cluster                        = var.vcenter_cluster
  host                           = var.vcenter_host != "" ? var.vcenter_host : null
  resource_pool                  = var.vcenter_resource_pool != "" ? var.vcenter_resource_pool : null
  datastore                      = var.vcenter_datastore
  folder                         = var.vcenter_folder != "" ? var.vcenter_folder : null
  set_host_for_datastore_uploads = true

  # Virtual machine identity and lifecycle
  vm_name             = var.vm_name
  convert_to_template = true

  # Hardware specifications
  guest_os_type        = var.vm_guest_os_type
  firmware             = var.vm_firmware
  CPUs                 = var.vm_cpu_cores
  RAM                  = var.vm_mem_size
  disk_controller_type = ["pvscsi"]

  storage {
    disk_size             = var.vm_disk_size
    disk_thin_provisioned = var.vm_disk_thin
  }

  # Virtual networking during build
  network_adapters {
    network      = var.vcenter_network
    network_card = "vmxnet3"
  }

  vm_version           = 19
  remove_cdrom         = true
  tools_upgrade_policy = true

  # Installation media configuration
  iso_paths    = var.iso_paths
  iso_url      = var.iso_url != "" ? var.iso_url : null
  iso_checksum = var.iso_checksum != "" ? var.iso_checksum : null

  # Attach Kickstart configuration as virtual CD-ROM volume labelled 'KS'
  cd_content = {
    "/ks.cfg" = local.kickstart_content
  }
  cd_label = "KS"

  # EFI GRUB boot command sequence for Anaconda unattended installation
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
  sources = ["source.vsphere-iso.oracle9"]

  # 1. Setup VMware Tools, GOSC prerequisites and baseline
  provisioner "shell" {
    script = "${path.root}/scripts/01_setup_vmtools.sh"
  }

  # 2. Generalize template and sanitize all machine/network artifacts
  provisioner "shell" {
    script = "${path.root}/scripts/02_clean_template.sh"
  }
}
