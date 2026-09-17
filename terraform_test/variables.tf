# ==============================================================================
# vSphere Provider Connection Variables
# ==============================================================================
variable "vsphere_server" {
  description = "Fully Qualified Domain Name or IPv4 address of the vCenter Server."
  type        = string
}

variable "vsphere_user" {
  description = "Administrative or service account username for vCenter authentication."
  type        = string
}

variable "vsphere_password" {
  description = "Password for the vCenter authentication account."
  type        = string
  sensitive   = true
}

variable "vsphere_insecure_connection" {
  description = "Set to true to disable SSL certificate verification."
  type        = bool
  default     = true
}

# ==============================================================================
# vSphere Infrastructure Targets
# ==============================================================================
variable "vsphere_datacenter" {
  description = "Target vSphere Datacenter name."
  type        = string
}

variable "vsphere_cluster" {
  description = "Target vSphere Compute Cluster name."
  type        = string
}

variable "vsphere_datastore" {
  description = "Target Datastore name for virtual machine storage."
  type        = string
}

variable "vsphere_template_name" {
  description = "Name of the existing golden template created by Packer."
  type        = string
}

# ==============================================================================
# Content Library Configuration
# ==============================================================================
variable "content_library_name" {
  description = "Name of the target Content Library to receive the golden template."
  type        = string
}

variable "content_library_item_name" {
  description = "Name of the item to create in the Content Library."
  type        = string
  default     = "tpl-ubuntu-2404-golden"
}

# ==============================================================================
# Inventory Folder Configuration
# ==============================================================================
variable "vm_folders" {
  description = "List of new inventory folders to create in bulk."
  type        = list(string)
  default     = ["App_Workloads", "Infra_Services"]
}

variable "vm_target_folder" {
  description = "Target inventory folder to place the newly provisioned VMs in."
  type        = string
  default     = "App_Workloads"
}

# ==============================================================================
# Networking & Host Configuration
# ==============================================================================
variable "esxi_hosts" {
  description = "List of ESXi host IP addresses or FQDNs in the cluster."
  type        = list(string)
}

variable "virtual_switch_name" {
  description = "Name of the standard vSwitch where port groups should be created."
  type        = string
  default     = "vSwitch0"
}

variable "port_groups" {
  description = "Map of port group names to configuration to provision on vSwitch0."
  type = map(object({
    vlan_id = optional(number, 0)
  }))
  default = {
    "VM Network 3" = { vlan_id = 0 }
    "VM Network 4" = { vlan_id = 0 }
  }
}

variable "default_domain_name" {
  description = "Default DNS domain name for guest customization."
  type        = string
  default     = "lab.local"
}

variable "default_dns_servers" {
  description = "Default DNS resolver IP addresses for guest customization."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_username" {
  description = "The OS username used by Ansible for SSH connections."
  type        = string
  default     = "<SSH_USERNAME>"
}

variable "ssh_public_key" {
  description = "Public SSH key to inject into authorized_keys for Ansible automation."
  type        = string
  default     = "<YOUR_SSH_PUBLIC_KEY>"
}

# ==============================================================================
# Virtual Machine Workload Definitions
# ==============================================================================
variable "vms" {
  description = "Map of virtual machines and their resource specifications."
  type = map(object({
    name         = string
    hostname     = string
    vm_id        = number
    cpu_count    = number
    memory_mb    = number
    disk_size_gb = number
    network_name = string
    ip_address   = string
    netmask      = number
    gateway      = string
    datastore_name = optional(string, null)
    host_name      = optional(string, null)
    folder_name    = optional(string, null)
    dns_servers    = optional(list(string), ["8.8.8.8"])
    domain_name  = optional(string, "lab.local")
    role         = optional(string, "standard")
    extra_config = optional(map(string), {})
  }))
}

variable "drs_rule_mandatory" {
  description = "Controls whether the DRS anti-affinity rule is mandatory (hard rule, prod) or preferential (soft rule, lab)."
  type        = bool
  default     = false
}

