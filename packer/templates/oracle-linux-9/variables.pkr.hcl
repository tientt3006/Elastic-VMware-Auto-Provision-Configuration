# ==============================================================================
# Packer Variables Specification - Oracle Linux 9 Golden Template Pipeline
# ==============================================================================

# vCenter Connection Configuration
variable "vcenter_server" {
  type        = string
  description = "Fully qualified domain name or IP of the VMware vCenter Server."
}

variable "vcenter_user" {
  type        = string
  description = "Administrative user for vCenter API operations."
}

variable "vcenter_password" {
  type        = string
  description = "Password for vCenter administrative user."
  sensitive   = true
}

variable "vcenter_insecure_connection" {
  type        = bool
  description = "Allow self-signed or unverified SSL certificates."
  default     = true
}

# Infrastructure Placement
variable "vcenter_datacenter" {
  type        = string
  description = "Target vSphere Datacenter name."
}

variable "vcenter_cluster" {
  type        = string
  description = "Target vSphere Cluster name."
}

variable "vcenter_host" {
  type        = string
  description = "Designated active ESXi host within the cluster."
  default     = ""
}

variable "vcenter_resource_pool" {
  type        = string
  description = "Target Resource Pool (default: Resources or cluster root)."
  default     = ""
}

variable "vcenter_datastore" {
  type        = string
  description = "Target shared VMFS datastore."
}

variable "vcenter_folder" {
  type        = string
  description = "Target VM and Template folder in vCenter."
  default     = "Template"
}

variable "vcenter_network" {
  type        = string
  description = "Virtual network / portgroup used during the OS build phase."
}

# Virtual Machine Specifications
variable "vm_name" {
  type        = string
  description = "Name assigned to the golden template virtual machine in vCenter."
  default     = "tpl-oracle-linux-9-golden"
}

variable "vm_guest_os_type" {
  type        = string
  description = "vSphere guest OS identifier for Oracle Linux 9."
  default     = "oracleLinux9_64Guest"
}

variable "vm_firmware" {
  type        = string
  description = "Boot firmware architecture (efi or bios)."
  default     = "efi"
}

variable "boot_order" {
  type        = string
  description = "Boot priority order of VM devices."
  default     = "disk,cdrom"
}

variable "vm_cpu_cores" {
  type        = number
  description = "vCPU count during build."
  default     = 2
}

variable "vm_mem_size" {
  type        = number
  description = "Memory size in Megabytes during build."
  default     = 4096
}

variable "vm_disk_size" {
  type        = number
  description = "Root disk capacity in Megabytes."
  default     = 40960 # 40 GB
}

variable "vm_disk_thin" {
  type        = bool
  description = "Enable thin provisioning for the template disk."
  default     = true
}

# ISO Installation Media
variable "iso_paths" {
  type        = list(string)
  description = "Datastore path to the Oracle Linux 9 ISO installer."
}

variable "iso_url" {
  type        = string
  description = "Optional HTTP/HTTPS URL to download ISO directly if not pre-uploaded."
  default     = ""
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the ISO file (format: sha256:hash)."
  default     = "none"
}

# Template OS User Credentials
variable "ssh_username" {
  type        = string
  description = "Default administrative username created in template."
  default     = "sysadmin"
}

variable "ssh_password" {
  type        = string
  description = "Plaintext password for template user."
  sensitive   = true
}

variable "ssh_password_hash" {
  type        = string
  description = "SHA-512 crypt hash of the password for kickstart unattended install."
  sensitive   = true
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Optional SSH public key injected into authorized_keys."
  default     = ""
}

variable "ssh_timeout" {
  type        = string
  description = "Timeout duration waiting for SSH communicator."
  default     = "30m"
}
