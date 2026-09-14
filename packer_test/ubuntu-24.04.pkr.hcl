# ==============================================================================
# Automated Ubuntu 24.04 LTS Golden Image Template Pipeline for VMware vSphere
# Builds hardened, cloud-init ready template with open-vm-tools preinstalled
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

source "vsphere-iso" "ubuntu" {
  # vCenter connection configuration
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_user
  password            = var.vcenter_password
  insecure_connection = var.vcenter_insecure_connection

  # Infrastructure placement
  datacenter = var.vcenter_datacenter
  cluster    = var.vcenter_cluster
  datastore  = var.vcenter_datastore
  folder     = var.vcenter_folder

  # Virtual machine identity and lifecycle
  vm_name             = var.vm_name
  convert_to_template = true

  # Hardware specifications
  guest_os_type = "ubuntu64Guest"
  firmware      = "efi"
  CPUs          = var.vm_cpu_cores
  cpu_cores     = var.vm_cpu_sockets
  RAM           = var.vm_mem_size
  RAM_reserve_all = false

  # Storage configuration
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

  # Content Library ISO image source
  iso_paths = var.iso_paths

  # Autoinstall configuration delivery via virtual CD-ROM (cidata)
  # Packer generates an ISO from these files and attaches it as a second CD drive.
  # Cloud-init automatically discovers the volume labeled "cidata" at boot.
  # This approach eliminates all HTTP/firewall/WSL networking failure modes.
  cd_files = ["${path.root}/http/user-data", "${path.root}/http/meta-data"]
  cd_label = "cidata"

  # GRUB boot sequence for Ubuntu 24.04 Subiquity installer
  # Uses GRUB command line (c) instead of editor (e) to avoid line navigation issues.
  # 'search --set=root' auto-discovers the ISO device without hardcoding (cd0)/(hd0).
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "search --set=root --file /casper/vmlinuz<enter><wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud<enter><wait5s>",
    "initrd /casper/initrd<enter><wait5s>",
    "boot<enter>"
  ]

  # SSH communicator setup
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = var.ssh_timeout

  # Graceful guest shutdown
  shutdown_command = "echo '${var.ssh_password}' | sudo -S poweroff"
  shutdown_timeout = "5m"
}

build {
  sources = ["source.vsphere-iso.ubuntu"]

  # Step 1-4: Automated baseline hardening and OS generalization
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    execute_command = "echo '${var.ssh_password}' | sudo -S -E sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "${path.root}/scripts/01_install_open_vm_tools.sh",
      "${path.root}/scripts/02_harden_ssh.sh",
      "${path.root}/scripts/03_configure_ufw.sh",
      "${path.root}/scripts/04_generalize_template.sh"
    ]
  }
}
