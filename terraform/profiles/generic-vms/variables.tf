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
  description = "Password for the vCenter authentication account (supplied via TF_VAR_vsphere_password)."
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
  description = "Default Datastore name for virtual machine storage."
  type        = string
}

variable "vsphere_template_name" {
  description = "Name of the existing golden template created by Packer."
  type        = string
}

# ==============================================================================
# Inventory Folder Configuration
# ==============================================================================
variable "vm_folders" {
  description = "List of new inventory folders to create in bulk."
  type        = list(string)
  default     = []
}

variable "vm_target_folder" {
  description = "Default target inventory folder to place the newly provisioned VMs in."
  type        = string
  default     = ""
}

# ==============================================================================
# Networking & Host Configuration
# ==============================================================================
variable "esxi_hosts" {
  description = "List of ESXi host IP addresses or FQDNs in the cluster (for port group creation)."
  type        = list(string)
  default     = []
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
  default = {}
}

variable "default_domain_name" {
  description = "Default DNS domain name for guest customization."
  type        = string
  default     = "lab.local"
}

variable "default_dns_servers" {
  description = "Default DNS resolver IP addresses for guest customization."
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "ssh_username" {
  description = "The OS username used for SSH administration."
  type        = string
  default     = "sysops"
}

variable "ssh_public_key" {
  description = "Public SSH key to inject into authorized_keys for automation."
  type        = string
  default     = ""
}

# ==============================================================================
# Virtual Machine Workload Definitions (Generalized Map)
# ==============================================================================
variable "vms" {
  description = "Map of virtual machines and their resource specifications."
  type = map(object({
    name           = string
    hostname       = string
    vm_id          = number
    cpu_count      = number
    memory_mb      = number
    disk_size_gb   = number
    network_name   = string
    ip_address     = string
    netmask        = number
    gateway        = string
    datastore_name = optional(string, null)
    host_name      = optional(string, null)
    folder_name    = optional(string, null)
    dns_servers    = optional(list(string), null)
    domain_name    = optional(string, null)
    role           = optional(string, "generic")
    extra_config   = optional(map(string), {})
  }))
}

# ==============================================================================
# DRS Cluster Rules Configuration
# ==============================================================================
variable "enable_drs_rule" {
  description = "Enable DRS Anti-Affinity rule for provisioned virtual machines."
  type        = bool
  default     = false
}

variable "drs_rule_mandatory" {
  description = "Controls whether the DRS anti-affinity rule is mandatory (hard rule) or preferential (soft rule)."
  type        = bool
  default     = false
}

# ==============================================================================
# Ansible Inventory Generation Options
# ==============================================================================
variable "generate_ansible_inventory" {
  description = "Whether to generate an automated Ansible hosts.yml inventory file upon completion."
  type        = bool
  default     = true
}

variable "ansible_inventory_path" {
  description = "Destination path for the generated Ansible inventory. Defaults to ./hosts.yml in the profile directory."
  type        = string
  default     = ""
}
