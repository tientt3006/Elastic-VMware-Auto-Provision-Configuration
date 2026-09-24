output "library_id" {
  description = "ID of the target Content Library."
  value       = data.vsphere_content_library.library.id
}

output "item_id" {
  description = "ID of the created Content Library item."
  value       = vsphere_content_library_item.item.id
}

output "item_name" {
  description = "Name of the created Content Library item."
  value       = vsphere_content_library_item.item.name
}
