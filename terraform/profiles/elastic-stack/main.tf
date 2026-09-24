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
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "source_template" {
  name          = var.vsphere_template_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# Dynamic Data Sources for Per-VM Overrides
data "vsphere_datastore" "vm_datastores" {
  for_each      = toset([for k, vm in var.vms : vm.datastore_name if vm.datastore_name != null])
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "vm_hosts" {
  for_each      = toset([for k, vm in var.vms : vm.host_name if vm.host_name != null])
  name          = each.value
  datacenter_id = data.vsphere_datacenter.datacenter.id
}



# ==============================================================================
# Module: Folder Provisioning (Bulk Creation)
# ==============================================================================
module "folder" {
  source = "../../modules/folder"

  datacenter_id = data.vsphere_datacenter.datacenter.id
  folder_names  = var.vm_folders
  folder_type   = "vm"
}

# ==============================================================================
# Module: Content Library Synchronization
# Clones source golden template to target Content Library without deleting source
# ==============================================================================
# module "content_library" {
#   source = "../../modules/content_library"
#
#   content_library_name = var.content_library_name
#   item_name            = var.content_library_item_name
#   item_description     = "Ubuntu 24.04 LTS Golden Template synchronized from VM Template folder"
#   source_vm_uuid       = data.vsphere_virtual_machine.source_template.id
#   item_type            = "ovf"
# }

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

  datacenter_id                   = data.vsphere_datacenter.datacenter.id
  resource_pool_id                = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id                    = data.vsphere_datastore.datastore.id
  template_id                     = data.vsphere_virtual_machine.source_template.id
  template_guest_id               = data.vsphere_virtual_machine.source_template.guest_id
  template_firmware               = data.vsphere_virtual_machine.source_template.firmware
  template_scsi_type              = data.vsphere_virtual_machine.source_template.scsi_type
  template_network_interface_type = data.vsphere_virtual_machine.source_template.network_interface_types[0]
  template_disk_thin_provisioned  = data.vsphere_virtual_machine.source_template.disks[0].thin_provisioned
  
  # Default Global Fallbacks
  folder                          = try(module.folder.folder_paths[var.vm_target_folder], null)
  default_domain_name             = var.default_domain_name
  default_dns_servers             = var.default_dns_servers
  ssh_public_key                  = var.ssh_public_key
  ssh_username                    = var.ssh_username

  # Override Mappings
  datastore_mapping               = { for k, v in data.vsphere_datastore.vm_datastores : k => v.id }
  host_mapping                    = { for k, v in data.vsphere_host.vm_hosts : k => v.id }
  folder_mapping                  = module.folder.folder_paths

  vms = {
    for k, vm in var.vms : k => merge(vm, {
      network_id = data.vsphere_network.networks[vm.network_name].id
    })
  }

  depends_on = [
    module.folder,
    module.network
  ]
}

# ==============================================================================
# Module: DRS Anti-Affinity Rule (Cluster Workload Separation)
# ==============================================================================
module "cluster_rules" {
  source = "../../modules/cluster_rules"

  compute_cluster_id  = data.vsphere_compute_cluster.cluster.id
  rule_name           = "elastic-cluster-anti-affinity"
  virtual_machine_ids = [
    for k, vm in module.compute.virtual_machines : vm.id
    if can(regex("elastic", k)) || can(regex("elastic", vm.name))
  ]
  mandatory           = var.drs_rule_mandatory
  enabled             = false

  # depends_on = [module.compute]
}

# ==============================================================================
# Dynamic Ansible Inventory Generation
# Exports provisioned VM topology directly to ansible inventory
# ==============================================================================
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/products/elastic-stack/inventories/lab/hosts.yml"
  file_permission = "0644"
  content         = templatefile("${path.module}/templates/hosts.yml.tpl", {
    vms          = var.vms
    ssh_username = var.ssh_username
  })

  depends_on = [module.compute]
}

