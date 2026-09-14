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
  folder           = var.folder
  resource_pool_id = var.resource_pool_id
  datastore_id     = var.datastore_id

  num_cpus = each.value.cpu_count
  memory   = each.value.memory_mb
  guest_id = var.template_guest_id
  firmware = var.template_firmware

  memory_hot_add_enabled = true
  cpu_hot_add_enabled    = true
  cpu_hot_remove_enabled = true

  scsi_type = var.template_scsi_type

  network_interface {
    network_id   = each.value.network_id
    adapter_type = var.template_network_interface_type
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size_gb
    thin_provisioned = var.template_disk_thin_provisioned
  }

  clone {
    template_uuid = var.template_id
  }

  wait_for_guest_net_routable = true
  wait_for_guest_net_timeout  = 5

  extra_config = merge(
    {
      "guestinfo.node.id"           = tostring(each.value.vm_id)
      "guestinfo.node.role"         = try(each.value.role, "standard")
      "guestinfo.metadata"          = base64encode(<<-EOF
        instance-id: "${each.value.name}"
        local-hostname: "${each.value.hostname}"
      EOF
      )
      "guestinfo.metadata.encoding"  = "base64"
      "guestinfo.userdata"          = base64encode(<<-EOF
        #cloud-config
        hostname: ${each.value.hostname}
        fqdn: ${each.value.hostname}.${coalesce(each.value.domain_name, var.default_domain_name)}
        manage_etc_hosts: true

        write_files:
          - path: /etc/netplan/01-netcfg.yaml
            permissions: '0600'
            owner: root:root
            content: |
              network:
                version: 2
                renderer: networkd
                ethernets:
                  ens33:
                    match:
                      name: "en*"
                    dhcp4: false
                    dhcp6: false
                    addresses:
                      - ${each.value.ip_address}/${each.value.netmask}
                    routes:
                      - to: default
                        via: ${each.value.gateway}
                    nameservers:
                      addresses: [${join(", ", [for dns in coalesce(each.value.dns_servers, var.default_dns_servers) : "\"${dns}\""])}]

        runcmd:
          - rm -f /etc/netplan/50-cloud-init.yaml /etc/netplan/99-netcfg-vmware.yaml
          - netplan apply
          - mkdir -p /home/svc_admin/.ssh
          - echo "${var.ssh_public_key}" >> /home/svc_admin/.ssh/authorized_keys
          - sort -u /home/svc_admin/.ssh/authorized_keys -o /home/svc_admin/.ssh/authorized_keys
          - chown -R svc_admin:svc_admin /home/svc_admin/.ssh
          - chmod 700 /home/svc_admin/.ssh
          - chmod 600 /home/svc_admin/.ssh/authorized_keys
      EOF
      )
      "guestinfo.userdata.encoding"  = "base64"
    },
    try(each.value.extra_config, {})
  )

  lifecycle {
    ignore_changes = [
      clone,
      disk,
    ]
  }
}
