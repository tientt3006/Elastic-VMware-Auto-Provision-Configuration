output "virtual_machines" {
  description = "Detailed mapping of all provisioned virtual machines."
  value       = module.compute.virtual_machines
}

output "vm_ip_list" {
  description = "List of configured IP addresses for all provisioned virtual machines."
  value       = module.compute.vm_ip_list
}

output "ansible_inventory_file" {
  description = "Path to the generated Ansible inventory file (if enabled)."
  value       = var.generate_ansible_inventory ? (var.ansible_inventory_path != "" ? var.ansible_inventory_path : "${path.module}/hosts.yml") : null
}
