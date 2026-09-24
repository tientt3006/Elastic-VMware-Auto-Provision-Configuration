variable "datacenter_id" {
  description = "The Managed Object ID of the target vSphere Datacenter."
  type        = string
}

variable "esxi_hosts" {
  description = "List of ESXi host names or IP addresses in the cluster."
  type        = list(string)
}

variable "virtual_switch_name" {
  description = "Name of the standard vSwitch where port groups should be added."
  type        = string
  default     = "vSwitch0"
}

variable "port_groups" {
  description = "Map of port group names to configuration (e.g. vlan_id)."
  type = map(object({
    vlan_id = optional(number, 0)
  }))
}
