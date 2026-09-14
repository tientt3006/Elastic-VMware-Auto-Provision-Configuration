# ==============================================================================
# Input Variables Specification for Ubuntu 24.04 VMware Template Pipeline
# ==============================================================================

variable "vcenter_server" {
  type        = string
  description = "Fully qualified domain name or IP address of the vCenter Server instance."
  default     = "10.255.242.106"
}

variable "vcenter_user" {
  type        = string
  description = "Administrative or service account username for vCenter authentication."
  default     = "administrator@vsphere.local"
}

variable "vcenter_password" {
  type        = string
  description = "Password corresponding to the vCenter user account."
  sensitive   = true
}

variable "vcenter_insecure_connection" {
  type        = bool
  description = "Set to true to skip TLS certificate validation for self-signed vCenter certificates."
  default     = true
}

variable "vcenter_datacenter" {
  type        = string
  description = "Target vSphere Datacenter object name."
  default     = "Datacenter"
}

variable "vcenter_cluster" {
  type        = string
  description = "Target vSphere Compute Cluster name hosting ESXi hypervisors."
  default     = "Cluster1"
}

variable "vcenter_datastore" {
  type        = string
  description = "Target datastore name used for VM disk allocation."
  default     = "DS_100_3"
}

variable "vcenter_network" {
  type        = string
  description = "Target virtual switch portgroup providing network connectivity and active DHCP service."
  default     = "VM Network"
}

variable "vcenter_folder" {
  type        = string
  description = "Target virtual machine inventory folder for template organization."
  default     = "VM Template"
}

variable "iso_paths" {
  type        = list(string)
  description = "List containing the datastore path to the Ubuntu 24.04 live server ISO image."
  default = [
    "[DS_100_3] contentlib-a0bc3584-8b7c-40cc-b2fd-bae7a6b9bf6c/befc5a25-2315-479a-833a-2cc168de715c/ubuntu-24.04.4-live-server-amd64_58a8cfa8-32e5-437c-b161-b18e4dc8d7aa.iso"
  ]
}

variable "vm_name" {
  type        = string
  description = "Name assigned to the virtual machine during build and converted template."
  default     = "tpl-ubuntu-2404-golden"
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of virtual CPU cores allocated per socket."
  default     = 2
}

variable "vm_cpu_sockets" {
  type        = number
  description = "Number of virtual CPU sockets allocated."
  default     = 1
}

variable "vm_mem_size" {
  type        = number
  description = "Size of system memory allocated to the virtual machine in megabytes."
  default     = 4096
}

variable "vm_disk_size" {
  type        = number
  description = "Size of primary OS virtual disk in megabytes (40960 MB = 40 GB)."
  default     = 40960
}

variable "vm_disk_thin" {
  type        = bool
  description = "Flag enabling thin disk provisioning format to conserve physical storage."
  default     = true
}

variable "ssh_username" {
  type        = string
  description = "Default administrative username created via cloud-init autoinstall."
  default     = "svc_admin"
}

variable "ssh_password" {
  type        = string
  description = "Password for the administrative user to establish SSH connectivity."
  sensitive   = true
  default     = "UbuntuBuildPassword2026!"
}

variable "ssh_timeout" {
  type        = string
  description = "Maximum duration Packer waits for SSH service availability before terminating."
  default     = "30m"
}

variable "http_directory" {
  type        = string
  description = "Local directory path containing cloud-init user-data and meta-data files."
  default     = "http"
}

variable "http_ip" {
  type        = string
  description = "Routable IP address of the host running Packer, reachable from the guest VM."
  default     = "10.255.245.20"
}

variable "http_bind_address" {
  type        = string
  description = "Network address on the host to bind the internal HTTP server."
  default     = "0.0.0.0"
}

variable "http_port_min" {
  type        = number
  description = "Minimum TCP port bound by Packer internal web server serving autoinstall files."
  default     = 8120
}

variable "http_port_max" {
  type        = number
  description = "Maximum TCP port bound by Packer internal web server serving autoinstall files."
  default     = 8130
}
