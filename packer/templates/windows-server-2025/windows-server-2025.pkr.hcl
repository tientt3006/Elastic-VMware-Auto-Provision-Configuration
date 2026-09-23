# ==============================================================================
# Automated Windows Server 2025 Golden Image Pipeline for VMware vSphere
# Built on HashiCorp Packer vsphere-iso & Broadcom reference architecture
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

source "vsphere-iso" "windows-server-2025" {
  # --- vCenter Server Connection & Authentication ---
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_user
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure_connection

  # --- vSphere Infrastructure Placement ---
  datacenter    = var.vcenter_datacenter
  cluster       = var.vcenter_cluster
  datastore     = var.vcenter_datastore
  folder        = var.vcenter_folder
  resource_pool = var.vcenter_resource_pool

  # --- Virtual Machine Hardware Specification ---
  vm_name              = var.vm_name
  guest_os_type        = var.guest_os_type
  firmware             = var.vm_firmware
  CPUs                 = var.vm_cpu_cores * var.vm_cpu_sockets
  cpu_cores            = var.vm_cpu_cores
  CPU_hot_plug         = true
  RAM                  = var.vm_mem_size
  RAM_hot_plug         = true
  cdrom_type           = var.vm_cdrom_type
  disk_controller_type = var.vm_disk_controller_type

  storage {
    disk_size             = var.vm_disk_size
    disk_thin_provisioned = var.vm_disk_thin
  }

  network_adapters {
    network      = var.vcenter_network
    network_card = var.vm_network_card
  }

  # --- Removable Media (Installer ISO, VMware Tools & Autounattend CD) ---
  iso_paths = var.iso_paths

  cd_files = [
    "${path.root}/scripts/windows-vmtools.ps1",
    "${path.root}/scripts/windows-init.ps1"
  ]

  cd_content = {
    "autounattend.xml" = templatefile("${path.root}/data/autounattend.pkrtpl.hcl", {
      winrm_username       = var.winrm_username
      winrm_password       = var.winrm_password
      vm_inst_os_image     = var.vm_inst_os_image
      vm_inst_os_eval      = var.vm_inst_os_eval
      vm_guest_os_language = var.vm_guest_os_language
      vm_guest_os_keyboard = var.vm_guest_os_keyboard
      vm_guest_os_timezone = var.vm_guest_os_timezone
    })
  }

  # --- Boot & Unattended Keystroke Sequence ---
  boot_order   = var.boot_order
  boot_wait    = var.boot_wait
  boot_command = var.boot_command

  # --- Communicator Specification (WinRM over HTTP) ---
  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_port     = var.winrm_port
  winrm_timeout  = var.winrm_timeout
  winrm_insecure = true
  winrm_use_ssl  = false

  # --- Shutdown & Template Conversion ---
  shutdown_command    = var.shutdown_command
  shutdown_timeout    = "20m"
  convert_to_template = var.convert_to_template
}

build {
  sources = ["source.vsphere-iso.windows-server-2025"]

  provisioner "powershell" {
    scripts = [
      "${path.root}/scripts/windows-prepare.ps1"
    ]
  }
}
