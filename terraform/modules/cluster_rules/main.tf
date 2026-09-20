resource "vsphere_compute_cluster_vm_anti_affinity_rule" "vm_anti_affinity_rule" {
  count               = length(var.virtual_machine_ids) > 1 ? 1 : 0
  name                = var.rule_name
  compute_cluster_id  = var.compute_cluster_id
  virtual_machine_ids = var.virtual_machine_ids
  mandatory           = var.mandatory
  enabled             = var.enabled
}
