variable "content_library_name" {
  description = "Name of the target Content Library in vCenter."
  type        = string
}

variable "item_name" {
  description = "Name of the item to create in the Content Library."
  type        = string
}

variable "item_description" {
  description = "Description for the Content Library item."
  type        = string
  default     = "VM template cloned from vCenter inventory"
}

variable "source_vm_uuid" {
  description = "The Managed Object ID (MOID) or UUID of the source virtual machine / template to clone."
  type        = string
}

variable "item_type" {
  description = "Type of content library item (e.g. ovf, vm-template, iso)."
  type        = string
  default     = "ovf"
}
