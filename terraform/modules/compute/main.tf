terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.6.0"
    }
  }
}

resource "vsphere_virtual_machine" "vm" {
  for_each = var.vms

  name             = each.value.name
  resource_pool_id = var.resource_pool_id

  # Inheritance and Override Pattern for Storage, Host, and Folder
  datastore_id   = try(var.datastore_mapping[each.value.datastore_name], var.datastore_id)
  host_system_id = try(var.host_mapping[each.value.host_name], null)
  folder         = each.value.folder_name != null && each.value.folder_name != "" ? try(var.folder_mapping[each.value.folder_name], each.value.folder_name) : var.folder

  num_cpus = each.value.cpu_count
  memory   = each.value.memory_mb

  guest_id = coalesce(try(each.value.template_guest_id, null), var.template_guest_id)
  firmware = coalesce(try(each.value.template_firmware, null), var.template_firmware)

  memory_hot_add_enabled = coalesce(try(each.value.memory_hot_add_enabled, null), true)
  cpu_hot_add_enabled    = coalesce(try(each.value.cpu_hot_add_enabled, null), true)
  cpu_hot_remove_enabled = true

  scsi_type = coalesce(try(each.value.template_scsi_type, null), var.template_scsi_type)

  network_interface {
    network_id   = each.value.network_id
    adapter_type = coalesce(try(each.value.template_network_interface_type, null), var.template_network_interface_type)
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size_gb
    thin_provisioned = coalesce(try(each.value.disk_thin_provisioned, null), try(each.value.template_disk_thin_provisioned, null), var.template_disk_thin_provisioned)
    eagerly_scrub    = coalesce(try(each.value.disk_eagerly_scrub, null), false)
    unit_number      = 0
  }

  dynamic "disk" {
    for_each = coalesce(try(each.value.extra_disks, null), [])
    content {
      label            = coalesce(disk.value.label, "disk${disk.key + 1}")
      size             = disk.value.size_gb
      thin_provisioned = coalesce(try(disk.value.thin_provisioned, null), true)
      eagerly_scrub    = coalesce(try(disk.value.eagerly_scrub, null), false)
      unit_number      = disk.key >= 6 ? disk.key + 2 : disk.key + 1
      datastore_id     = disk.value.datastore_name != null && disk.value.datastore_name != "" ? try(var.datastore_mapping[disk.value.datastore_name], null) : null
    }
  }

  clone {
    template_uuid = coalesce(try(each.value.template_id, null), var.template_id)

    customize {
      # Windows Guest Customization (Sysprep)
      dynamic "windows_options" {
        for_each = can(regex("(?i)win", coalesce(try(each.value.template_guest_id, null), var.template_guest_id))) ? [1] : []
        content {
          computer_name  = substr(replace(each.value.hostname, "_", "-"), 0, 15)
          admin_password = try(
            each.value.admin_password != null && each.value.admin_password != "" ? each.value.admin_password : (
              var.windows_admin_password != null && var.windows_admin_password != "" ? var.windows_admin_password : null
            ),
            null
          )
          workgroup      = coalesce(try(each.value.workgroup, null), var.windows_workgroup, "WORKGROUP")
          auto_logon     = false
        }
      }

      # Linux Guest Customization (Open-VM-Tools / Cloud-Init)
      dynamic "linux_options" {
        for_each = !can(regex("(?i)win", coalesce(try(each.value.template_guest_id, null), var.template_guest_id))) ? [1] : []
        content {
          host_name = each.value.hostname
          domain    = coalesce(each.value.domain_name, var.default_domain_name)
        }
      }

      network_interface {
        ipv4_address = each.value.ip_address
        ipv4_netmask = each.value.netmask
      }
      ipv4_gateway    = each.value.gateway
      dns_server_list = try(length(each.value.dns_servers) > 0 ? each.value.dns_servers : null, var.default_dns_servers)
    }
  }

  wait_for_guest_net_routable = true
  wait_for_guest_net_timeout  = 5

  extra_config = merge(
    merge(
      each.value.vm_id != null ? { "guestinfo.node.id" = tostring(each.value.vm_id) } : {},
      each.value.role != null && each.value.role != "" && each.value.role != "generic" && each.value.role != "standard" ? { "guestinfo.node.role" = each.value.role } : {},
      !can(regex("(?i)win", coalesce(try(each.value.template_guest_id, null), var.template_guest_id))) ? {
        "guestinfo.metadata" = base64encode(<<-EOF
          instance-id: "${each.value.name}"
          local-hostname: "${each.value.hostname}"
        EOF
        )
        "guestinfo.metadata.encoding" = "base64"
        "guestinfo.userdata" = base64encode(<<-EOF
        #cloud-config
        hostname: ${each.value.hostname}
        fqdn: ${each.value.hostname}.${coalesce(each.value.domain_name, var.default_domain_name)}
        manage_etc_hosts: true
%{if var.ssh_username != "" && !can(regex("<.*>", var.ssh_username)) && var.ssh_public_key != "" && !can(regex("<.*>", var.ssh_public_key))~}

        runcmd:
          - mkdir -p /home/${var.ssh_username}/.ssh
          - echo "${var.ssh_public_key}" >> /home/${var.ssh_username}/.ssh/authorized_keys
          - sort -u /home/${var.ssh_username}/.ssh/authorized_keys -o /home/${var.ssh_username}/.ssh/authorized_keys
          - chown -R ${var.ssh_username}:${var.ssh_username} /home/${var.ssh_username}/.ssh
          - chmod 700 /home/${var.ssh_username}/.ssh
          - chmod 600 /home/${var.ssh_username}/.ssh/authorized_keys
%{endif~}
      EOF
        )
        "guestinfo.userdata.encoding" = "base64"
      } : {}
    ),
    try(each.value.extra_config, {})
  )

  lifecycle {
    ignore_changes = [
      clone,
      disk,
    ]
  }
}
