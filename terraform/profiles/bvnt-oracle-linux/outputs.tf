# ==============================================================================
# Outputs - BVNT Oracle Linux 9 Profile
# ==============================================================================

output "virtual_machines" {
  description = "Detailed mapping of provisioned Oracle Linux virtual machines."
  value       = module.compute.virtual_machines
}

output "vm_ip_list" {
  description = "Configured IP list of provisioned Oracle Linux virtual machines."
  value       = module.compute.vm_ip_list
}
