output "rule_id" {
  description = "The ID of the provisioned DRS anti-affinity rule."
  value       = try(vsphere_compute_cluster_vm_anti_affinity_rule.vm_anti_affinity_rule[0].id, null)
}
