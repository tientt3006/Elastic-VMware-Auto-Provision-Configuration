{
  "__version": "2.13.0",
  "__comments": "VMware vCenter Server Appliance 8.0/7.0 Unattended Embedded Deployment on Standalone ESXi Template",
  "new_vcsa": {
    "esxi": {
      "hostname": "${ESXI_HOSTNAME}",
      "username": "${ESXI_USERNAME}",
      "password": "${ESXI_PASSWORD}",
      "deployment_network": "${DEPLOYMENT_NETWORK}",
      "datastore": "${DATASTORE_NAME}"
    },
    "appliance": {
      "__comments": "Supported deployment options: tiny, small, medium, large, xlarge",
      "deployment_option": "${VCSA_SIZE}",
      "name": "${VCSA_VM_NAME}",
      "thick_provision": false
    },
    "os": {
      "password": "${VCSA_ROOT_PASSWORD}",
      "ntp_servers": "${NTP_SERVERS}",
      "ssh_enable": true
    },
    "sso": {
      "password": "${SSO_ADMIN_PASSWORD}",
      "domain_name": "${SSO_DOMAIN_NAME}"
    },
    "network": {
      "ip_family": "ipv4",
      "mode": "static",
      "ip": "${VCSA_STATIC_IP}",
      "dns_servers": [
        "${DNS_SERVER_PRIMARY}",
        "${DNS_SERVER_SECONDARY}"
      ],
      "prefix": "${VCSA_PREFIX}",
      "gateway": "${VCSA_GATEWAY}",
      "system_name": "${VCSA_FQDN}"
    }
  },
  "ceip": {
    "settings": {
      "ceip_enabled": false
    }
  }
}
