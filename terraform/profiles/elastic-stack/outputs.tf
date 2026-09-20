output "created_folders" {
  description = "Inventory paths and IDs of the bulk created folders."
  value       = module.folder.folders
}

# output "content_library_item" {
#   description = "ID and Name of the synchronized Content Library Item"
#   value = {
#     id   = module.content_library.item_id
#     name = module.content_library.item_name
#   }
# }

output "provisioned_port_groups" {
  description = "List of standard port groups created across ESXi cluster hosts."
  value       = module.network.port_group_names
}

output "virtual_machines" {
  description = "Comprehensive details of all provisioned virtual machines."
  value       = module.compute.virtual_machines
}

output "ansible_inventory_hosts" {
  description = "Host IP addresses formatted for downstream configuration management."
  value       = module.compute.vm_ip_list
}

output "ansible_inventory_path" {
  description = "Path to the dynamically generated Ansible inventory file."
  value       = local_file.ansible_inventory.filename
}

output "drs_anti_affinity_rule_id" {
  description = "ID of the provisioned DRS Anti-Affinity rule."
  value       = module.cluster_rules.rule_id
}
