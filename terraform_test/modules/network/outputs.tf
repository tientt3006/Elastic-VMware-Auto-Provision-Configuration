output "port_group_keys" {
  description = "Keys of all created host port groups."
  value       = keys(vsphere_host_port_group.port_groups)
}

output "port_group_names" {
  description = "List of configured port group names."
  value       = keys(var.port_groups)
}
