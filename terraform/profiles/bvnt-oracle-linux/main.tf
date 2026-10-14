# ==============================================================================
# Root Terraform Configuration - Oracle Linux 9 Workloads
# Target Environment: vcsa.bvnttwhcm.int (Bệnh viện Nhiệt đới Trung ương TP.HCM)
# ==============================================================================

provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = var.vsphere_insecure_connection
}

# ==============================================================================
# Infrastructure Discovery Data Sources
# ==============================================================================
data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "host" {
  count         = var.vsphere_host != "" ? 1 : 0
  name          = var.vsphere_host
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_resource_pool" "pool" {
  count         = var.vsphere_resource_pool != "" ? 1 : 0
  name          = var.vsphere_resource_pool
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vsphere_template_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "networks" {
  for_each      = toset([for vm in var.vms : vm.network_name])
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# ==============================================================================
# Module: Virtual Machine Provisioning (Oracle Linux 9)
# ==============================================================================
module "compute" {
  source = "../../modules/compute"

  datacenter_id    = data.vsphere_datacenter.datacenter.id
  resource_pool_id = try(data.vsphere_resource_pool.pool[0].id, data.vsphere_compute_cluster.cluster.resource_pool_id)
  datastore_id     = data.vsphere_datastore.datastore.id
  host_system_id   = try(data.vsphere_host.host[0].id, null)
  folder           = var.vm_target_folder != "" ? var.vm_target_folder : null

  template_id                     = data.vsphere_virtual_machine.template.id
  template_guest_id               = data.vsphere_virtual_machine.template.guest_id
  template_firmware               = data.vsphere_virtual_machine.template.firmware
  template_scsi_type              = data.vsphere_virtual_machine.template.scsi_type
  template_network_interface_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  template_disk_thin_provisioned  = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

  default_domain_name = var.default_domain_name
  default_dns_servers = var.default_dns_servers
  timezone            = var.timezone
  ssh_username        = var.ssh_username

  vms = {
    for k, vm in var.vms : k => merge(vm, {
      network_id = data.vsphere_network.networks[vm.network_name].id
    })
  }
}

# ==============================================================================
# Dynamic Ansible Inventory Generation
# ==============================================================================
resource "local_file" "ansible_inventory" {
  count           = var.generate_ansible_inventory ? 1 : 0
  filename        = var.ansible_inventory_path != "" ? var.ansible_inventory_path : "${path.module}/hosts.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.yml.tpl", {
    vms          = var.vms
    ssh_username = var.ssh_username
  })

  depends_on = [module.compute]
}
