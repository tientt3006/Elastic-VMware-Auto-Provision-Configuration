# ==============================================================================
# Variables Definition - BVNT Windows Server 2025 Profile
# ==============================================================================

variable "vsphere_server" {
  description = "Target vCenter Server FQDN or IP address."
  type        = string
}

variable "vsphere_user" {
  description = "vCenter administrator username."
  type        = string
}

variable "vsphere_password" {
  description = "vCenter administrator password."
  type        = string
  sensitive   = true
}

variable "vsphere_insecure_connection" {
  description = "Allow unverified SSL certificates."
  type        = bool
  default     = true
}

variable "vsphere_datacenter" {
  description = "Target vSphere Datacenter name."
  type        = string
}

variable "vsphere_cluster" {
  description = "Target vSphere Cluster name."
  type        = string
}

variable "vsphere_host" {
  description = "Specific target ESXi host name (pinned to single active host)."
  type        = string
  default     = ""
}

variable "vsphere_datastore" {
  description = "Target shared VMFS datastore."
  type        = string
}

variable "vsphere_resource_pool" {
  description = "Target Resource Pool name (or Resources / cluster root)."
  type        = string
  default     = ""
}

variable "vsphere_template_name" {
  description = "Source Golden VM Template name to clone from."
  type        = string
  default     = "tpl-windows-server-2025-golden"
}

variable "vm_target_folder" {
  description = "Target vCenter inventory folder for provisioned VMs."
  type        = string
  default     = "HIS-EMR VM"
}

variable "default_domain_name" {
  description = "Default DNS domain search suffix."
  type        = string
  default     = "bvnttwhcm.int"
}

variable "default_dns_servers" {
  description = "Default DNS resolvers list."
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "windows_admin_password" {
  description = "Administrator password applied during Windows Sysprep customization."
  type        = string
  sensitive   = true
  default     = "ayBHCMhtnnd2026"
}

variable "windows_workgroup" {
  description = "Windows Workgroup name."
  type        = string
  default     = "WORKGROUP"
}

variable "windows_timezone_code" {
  description = "Microsoft Windows Time Zone index (205 = SE Asia Standard Time UTC+07:00)."
  type        = number
  default     = 205
}

variable "generate_ansible_inventory" {
  description = "Generate an Ansible dynamic inventory file upon successful apply."
  type        = bool
  default     = true
}

variable "ansible_inventory_path" {
  description = "Path to write the generated Ansible inventory file."
  type        = string
  default     = ""
}

variable "vms" {
  description = "Map of virtual machines and their resource specifications."
  type = map(object({
    name           = string
    hostname       = string
    cpu_count      = number
    memory_mb      = number
    disk_size_gb   = number
    network_name   = string
    ip_address     = string
    netmask        = number
    gateway        = string
    role           = optional(string, "generic")
    dns_servers    = optional(list(string), null)
    domain_name    = optional(string, null)
    admin_password = optional(string, null)
    time_zone      = optional(number, null)
  }))
}
