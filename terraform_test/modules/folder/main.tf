terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.6.0"
    }
  }
}

resource "vsphere_folder" "vm_folders" {
  for_each      = toset(var.folder_names)
  path          = each.value
  type          = var.folder_type
  datacenter_id = var.datacenter_id
}
