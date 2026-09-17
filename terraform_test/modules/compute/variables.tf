variable "datacenter_id" {
  description = "The Managed Object ID of the target vSphere Datacenter."
  type        = string
}

variable "resource_pool_id" {
  description = "The Managed Object ID of the target Resource Pool or Cluster."
  type        = string
}

variable "datastore_id" {
  description = "The Managed Object ID of the target Datastore."
  type        = string
}

variable "template_id" {
  description = "UUID / MOID of the source template to clone from."
  type        = string
}

variable "template_guest_id" {
  description = "Guest OS ID of the source template."
  type        = string
  default     = "ubuntu64Guest"
}

variable "template_firmware" {
  description = "Firmware type of the source template (bios or efi)."
  type        = string
  default     = "efi"
}

variable "template_scsi_type" {
  description = "SCSI controller type of the source template."
  type        = string
  default     = "lsilogic"
}

variable "template_network_interface_type" {
  description = "Network interface adapter type of the source template."
  type        = string
  default     = "vmxnet3"
}

variable "template_disk_thin_provisioned" {
  description = "Whether the primary disk is thin provisioned."
  type        = bool
  default     = true
}

variable "folder" {
  description = "The inventory folder path to place the virtual machines in."
  type        = string
  default     = null
}

variable "default_domain_name" {
  description = "Default DNS search domain name."
  type        = string
  default     = "lab.local"
}

variable "datastore_mapping" {
  description = "Map of datastore names to their IDs for per-VM overrides."
  type        = map(string)
  default     = {}
}

variable "host_mapping" {
  description = "Map of host names to their IDs for per-VM overrides."
  type        = map(string)
  default     = {}
}

variable "folder_mapping" {
  description = "Map of folder names to their IDs for per-VM overrides."
  type        = map(string)
  default     = {}
}

variable "default_dns_servers" {
  description = "Default DNS servers list."
  type        = list(string)
  default     = ["8.8.8.8"]
}

variable "ssh_username" {
  description = "The OS username used for SSH connections."
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key to inject into authorized_keys for Ansible automation."
  type        = string
  default     = "<YOUR_SSH_PUBLIC_KEY>"
}

variable "vms" {
  description = "Map of virtual machines and their resource specifications."
  type = map(object({
    name         = string
    hostname     = string
    vm_id        = number
    cpu_count    = number
    memory_mb    = number
    disk_size_gb = number
    network_id   = string
    ip_address   = string
    netmask      = number
    gateway      = string
    dns_servers  = optional(list(string), ["8.8.8.8"])
    datastore_name = optional(string, null)
    host_name      = optional(string, null)
    folder_name    = optional(string, null)
    domain_name  = optional(string, "lab.local")
    role         = optional(string, "standard")
    extra_config = optional(map(string), {})
  }))
}
