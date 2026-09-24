# ==============================================================================
# Input Variables Specification for Windows Server 2025 VMware Template Pipeline
# Based on Broadcom / VMware packer-examples-for-vsphere standard
# ==============================================================================

variable "vcenter_server" {
  type        = string
  description = "Fully qualified domain name or IP address of the vCenter Server instance."
}

variable "vcenter_user" {
  type        = string
  description = "Administrative or service account username for vCenter authentication."
}

variable "vcenter_password" {
  type        = string
  description = "Password corresponding to the vCenter user account."
  sensitive   = true
}

variable "vcenter_insecure_connection" {
  type        = bool
  description = "Set to true to skip TLS certificate validation for self-signed vCenter certificates."
  default     = true
}

variable "vcenter_datacenter" {
  type        = string
  description = "Target vSphere Datacenter object name."
}

variable "vcenter_cluster" {
  type        = string
  description = "Target vSphere Compute Cluster name hosting ESXi hypervisors."
}

variable "vcenter_datastore" {
  type        = string
  description = "Target datastore name used for VM disk allocation."
}

variable "vcenter_network" {
  type        = string
  description = "Target virtual switch portgroup providing network connectivity and active DHCP service."
}

variable "vcenter_folder" {
  type        = string
  description = "Target virtual machine inventory folder for template organization."
  default     = ""
}

variable "vcenter_resource_pool" {
  type        = string
  description = "Target vSphere Resource Pool name within the cluster or standalone host."
  default     = ""
}

# --- Virtual Machine Hardware Specification ---

variable "vm_name" {
  type        = string
  description = "Name assigned to the virtual machine during build and converted template."
  default     = "template-windows-server-2025"
}

variable "guest_os_type" {
  type        = string
  description = "vSphere guest OS identifier (guestid). Defaults to Windows Server 2025 / Next (vSphere 8.x)."
  default     = "windows2022srvNext_64Guest"
}

variable "vm_firmware" {
  type        = string
  description = "Virtual machine firmware type ('efi-secure', 'efi', or 'bios')."
  default     = "efi-secure"
}

variable "vm_cpu_sockets" {
  type        = number
  description = "Number of virtual CPU sockets allocated."
  default     = 1
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of virtual CPU cores allocated per socket."
  default     = 4
}

variable "vm_mem_size" {
  type        = number
  description = "Size of system memory allocated to the virtual machine in megabytes."
  default     = 6144
}

variable "vm_disk_size" {
  type        = number
  description = "Virtual disk capacity allocated to the system in megabytes (defaults to 60 GB)."
  default     = 61440
}

variable "vm_disk_thin" {
  type        = bool
  description = "Provision virtual hard disk as thin-provisioned sparse disk."
  default     = true
}

variable "vm_disk_controller_type" {
  type        = list(string)
  description = "Type of virtual storage controller attached to the virtual machine."
  default     = ["pvscsi"]
}

variable "vm_network_card" {
  type        = string
  description = "Virtual network interface card hardware emulation model."
  default     = "vmxnet3"
}

variable "vm_cdrom_type" {
  type        = string
  description = "Virtual CD-ROM controller type ('sata' or 'ide')."
  default     = "sata"
}

# --- Removable Media Configuration ---

variable "iso_paths" {
  type        = list(string)
  description = "List of ISO paths attached to the VM. Must include the Windows installer ISO and the VMware Tools ISO."
}

# --- WinRM Communicator & Authentication ---

variable "winrm_username" {
  type        = string
  description = "Administrator account username for WinRM communicator connection."
  default     = "Administrator"
}

variable "winrm_password" {
  type        = string
  description = "Administrator account password used for WinRM and Windows local account."
  sensitive   = true
}

variable "winrm_port" {
  type        = number
  description = "TCP port used by WinRM listener (HTTP default 5985)."
  default     = 5985
}

variable "winrm_timeout" {
  type        = string
  description = "Maximum time duration to wait for WinRM connection to become active."
  default     = "4h"
}

# --- Windows Unattended Installation Parameters ---

variable "vm_inst_os_image" {
  type        = string
  description = "Name of the Windows image edition to install from the WIM image."
  default     = "Windows Server 2025 SERVERSTANDARD"
}

variable "vm_inst_os_eval" {
  type        = bool
  description = "Whether the installation uses evaluation media (skips product key)."
  default     = true
}

variable "vm_guest_os_language" {
  type        = string
  description = "Operating system UI and locale language code."
  default     = "en-US"
}

variable "vm_guest_os_keyboard" {
  type        = string
  description = "Operating system keyboard layout code."
  default     = "en-US"
}

variable "vm_guest_os_timezone" {
  type        = string
  description = "Operating system default timezone identifier."
  default     = "UTC"
}

# --- Boot and Lifecycle Controls ---

variable "boot_order" {
  type        = string
  description = "Boot device sequence priority ('disk,cdrom')."
  default     = "disk,cdrom"
}

variable "boot_wait" {
  type        = string
  description = "Time duration to wait before issuing boot commands."
  default     = "2s"
}

variable "boot_command" {
  type        = list(string)
  description = "Keystroke sequence sent upon power-on to bypass the 'Press any key to boot from CD' prompt."
  default     = ["<spacebar>"]
}

variable "shutdown_command" {
  type        = string
  description = "Command executed to gracefully power off Windows after provisioning."
  default     = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer complete shutdown\""
}

variable "convert_to_template" {
  type        = bool
  description = "Convert virtual machine to vSphere Template object upon successful completion."
  default     = true
}
