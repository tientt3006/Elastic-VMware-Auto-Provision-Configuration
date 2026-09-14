terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.6.0"
    }
  }
}

data "vsphere_content_library" "library" {
  name = var.content_library_name
}

resource "vsphere_content_library_item" "item" {
  name        = var.item_name
  description = var.item_description
  library_id  = data.vsphere_content_library.library.id
  source_uuid = var.source_vm_uuid
  type        = var.item_type

  lifecycle {
    ignore_changes = [
      description
    ]
  }
}
