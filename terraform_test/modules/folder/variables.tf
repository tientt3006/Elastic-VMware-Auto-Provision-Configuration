variable "datacenter_id" {
  description = "The Managed Object ID of the target vSphere Datacenter."
  type        = string
}

variable "folder_type" {
  description = "The type of folder to create. Options: vm, host, datastore, network."
  type        = string
  default     = "vm"
}

variable "folder_names" {
  description = "List of folder paths or names to create in bulk."
  type        = list(string)
}
