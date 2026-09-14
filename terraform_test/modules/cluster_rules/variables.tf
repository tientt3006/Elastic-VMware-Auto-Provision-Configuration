variable "compute_cluster_id" {
  description = "The ID of the vSphere compute cluster where rules will be created."
  type        = string
}

variable "rule_name" {
  description = "Name of the VM-VM anti-affinity rule."
  type        = string
  default     = "elastic-cluster-anti-affinity"
}

variable "virtual_machine_ids" {
  description = "List of virtual machine IDs to separate across distinct ESXi hosts."
  type        = list(string)
}

variable "mandatory" {
  description = "When true (hard rule), prevents VMs from running on the same host even if insufficient hosts exist. When false (soft/preferential rule), allows collocation if insufficient hosts exist."
  type        = bool
  default     = false
}

variable "enabled" {
  description = "Whether the DRS anti-affinity rule is enabled."
  type        = bool
  default     = true
}
