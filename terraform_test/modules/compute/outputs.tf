output "virtual_machines" {
  description = "Detailed mapping of all provisioned virtual machines."
  value = {
    for k, vm in vsphere_virtual_machine.vm : k => {
      id           = vm.id
      name         = vm.name
      guest_ip     = try(vm.default_ip_address, null)
      mac_address  = try(vm.network_interface[0].mac_address, null)
      num_cpus     = vm.num_cpus
      memory_mb    = vm.memory
      disk_size_gb = vm.disk[0].size
      power_state  = vm.power_state
      node_id      = try(vm.extra_config["guestinfo.node.id"], null)
      role         = try(vm.extra_config["guestinfo.node.role"], null)
    }
  }
}

output "vm_ip_list" {
  description = "List of configured IP addresses for all provisioned virtual machines."
  value       = [for k, vm in var.vms : vm.ip_address]
}
