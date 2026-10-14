# ==============================================================================
# Outputs - BVNT Windows Server 2025 Profile
# ==============================================================================

output "virtual_machines" {
  description = "Detailed mapping of provisioned Windows Server virtual machines."
  value       = module.compute.virtual_machines
}

output "vm_ip_list" {
  description = "Configured IP list of provisioned Windows Server virtual machines."
  value       = module.compute.vm_ip_list
}
