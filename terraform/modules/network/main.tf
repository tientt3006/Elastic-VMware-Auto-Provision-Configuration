terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.6.0"
    }
  }
}

data "vsphere_host" "hosts" {
  for_each      = toset(var.esxi_hosts)
  name          = each.value
  datacenter_id = var.datacenter_id
}

locals {
  host_pg_pairs = flatten([
    for host_name in var.esxi_hosts : [
      for pg_name, pg_cfg in var.port_groups : {
        key       = "${host_name}_${pg_name}"
        host_name = host_name
        pg_name   = pg_name
        vlan_id   = try(pg_cfg.vlan_id, 0)
      }
    ]
  ])
}

resource "vsphere_host_port_group" "port_groups" {
  for_each = { for pair in local.host_pg_pairs : pair.key => pair }

  name                = each.value.pg_name
  host_system_id      = data.vsphere_host.hosts[each.value.host_name].id
  virtual_switch_name = var.virtual_switch_name
  vlan_id             = each.value.vlan_id
}
