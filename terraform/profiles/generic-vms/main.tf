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

data "vsphere_datastore" "datastore" {
  count         = var.vsphere_datastore != "" && var.vsphere_datastore != null ? 1 : 0
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# Dynamic Multi-Template Discovery
locals {
  required_template_names = toset(compact(concat(
    var.vsphere_template_name != "" && var.vsphere_template_name != null ? [var.vsphere_template_name] : [],
    [for k, vm in var.vms : vm.template_name if vm.template_name != null && vm.template_name != ""]
  )))

  extra_datastore_names = flatten([
    for k, vm in var.vms : [
      for d in coalesce(try(vm.extra_disks, null), []) : d.datastore_name if d.datastore_name != null && d.datastore_name != ""
    ]
  ])

  all_custom_datastores = toset(compact(concat(
    [for k, vm in var.vms : vm.datastore_name if vm.datastore_name != null && vm.datastore_name != ""],
    local.extra_datastore_names
  )))

  all_custom_folders = toset(compact(concat(
    var.vm_folders,
    var.vm_target_folder != "" ? [var.vm_target_folder] : [],
    [for k, vm in var.vms : vm.folder_name if vm.folder_name != null && vm.folder_name != ""]
  )))
}

data "vsphere_virtual_machine" "source_templates" {
  for_each      = local.required_template_names
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# Dynamic Data Sources for Per-VM Overrides
data "vsphere_datastore" "vm_datastores" {
  for_each      = local.all_custom_datastores
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "vm_hosts" {
  for_each      = toset([for k, vm in var.vms : vm.host_name if vm.host_name != null && vm.host_name != ""])
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# ==============================================================================
# Module: Folder Provisioning (Bulk Creation)
# ==============================================================================
module "folder" {
  source = "../../modules/folder"

  datacenter_id = data.vsphere_datacenter.datacenter.id
  folder_names  = tolist(local.all_custom_folders)
  folder_type   = "vm"
}

# ==============================================================================
# Module: Network Provisioning
# Creates standard port groups across all ESXi hosts on vSwitch0
# ==============================================================================
module "network" {
  source = "../../modules/network"

  datacenter_id       = data.vsphere_datacenter.datacenter.id
  esxi_hosts          = var.esxi_hosts
  virtual_switch_name = var.virtual_switch_name
  port_groups         = var.port_groups
}

# ==============================================================================
# Dynamic Network Resolution for VM Interfaces
# Waits for module.network before querying newly provisioned port groups
# ==============================================================================
data "vsphere_network" "networks" {
  for_each      = toset([for vm in var.vms : vm.network_name])
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [module.network]
}

# ==============================================================================
# Module: Compute Provisioning (Customized Virtual Machines)
# ==============================================================================
module "compute" {
  source = "../../modules/compute"

  datacenter_id    = data.vsphere_datacenter.datacenter.id
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = try(data.vsphere_datastore.datastore[0].id, length(local.all_custom_datastores) > 0 ? data.vsphere_datastore.vm_datastores[tolist(local.all_custom_datastores)[0]].id : "")

  # Global fallbacks (used if a VM does not override)
  template_id                     = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].id : ""
  template_guest_id               = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].guest_id : "ubuntu64Guest"
  template_firmware               = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].firmware : "efi"
  template_scsi_type              = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].scsi_type : "pvscsi"
  template_network_interface_type = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].network_interface_types[0] : "vmxnet3"
  template_disk_thin_provisioned  = length(local.required_template_names) > 0 ? data.vsphere_virtual_machine.source_templates[tolist(local.required_template_names)[0]].disks[0].thin_provisioned : true

  # Default Global Fallbacks
  folder                 = var.vm_target_folder != "" ? try(module.folder.folder_paths[var.vm_target_folder], null) : null
  default_domain_name    = var.default_domain_name
  default_dns_servers    = var.default_dns_servers
  ssh_public_key         = var.ssh_public_key
  ssh_username           = var.ssh_username
  windows_admin_password = var.windows_admin_password
  windows_workgroup      = var.windows_workgroup

  # Override Mappings
  datastore_mapping = { for k, v in data.vsphere_datastore.vm_datastores : k => v.id }
  host_mapping      = { for k, v in data.vsphere_host.vm_hosts : k => v.id }
  folder_mapping    = module.folder.folder_paths

  vms = {
    for k, vm in var.vms : k => merge(vm, {
      network_id = data.vsphere_network.networks[vm.network_name].id

      # Dynamic Per-VM Template Metadata Resolution
      template_id                     = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].id
      template_guest_id               = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].guest_id
      template_firmware               = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].firmware
      template_scsi_type              = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].scsi_type
      template_network_interface_type = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].network_interface_types[0]
      template_disk_thin_provisioned  = data.vsphere_virtual_machine.source_templates[vm.template_name != null && vm.template_name != "" ? vm.template_name : var.vsphere_template_name].disks[0].thin_provisioned
    })
  }

  depends_on = [
    module.folder,
    module.network
  ]
}

# ==============================================================================
# Module: DRS Anti-Affinity Rule (Optional)
# ==============================================================================
module "cluster_rules" {
  source = "../../modules/cluster_rules"

  compute_cluster_id  = data.vsphere_compute_cluster.cluster.id
  rule_name           = "generic-vms-anti-affinity"
  virtual_machine_ids = [for k, vm in module.compute.virtual_machines : vm.id]
  mandatory           = var.drs_rule_mandatory
  enabled             = var.enable_drs_rule
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
