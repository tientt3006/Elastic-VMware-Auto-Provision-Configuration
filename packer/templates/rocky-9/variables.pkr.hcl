# ==============================================================================
# Input Variables Specification for Rocky Linux 9 Minimal VMware Template
# ==============================================================================

variable "vcenter_server" {
  type        = string
  description = "Fully qualified domain name or IP address of the vCenter Server instance."
}

variable "vcenter_user" {
  type        = string
  description = "Administrative account username for vCenter authentication."
}

variable "vcenter_password" {
  type        = string
  description = "Password corresponding to the vCenter user account."
  sensitive   = true
}

variable "vcenter_insecure_connection" {
  type        = bool
  description = "Set to true to skip TLS certificate validation for self-signed certificates."
  default     = true
}

variable "vcenter_datacenter" {
  type        = string
  description = "Target vSphere Datacenter object name."
}

variable "vcenter_cluster" {
  type        = string
  description = "Target vSphere Compute Cluster name hosting ESXi hypervisors."
}

variable "vcenter_datastore" {
  type        = string
  description = "Target datastore name used for VM disk allocation."
}

variable "vcenter_network" {
  type        = string
  description = "Target virtual switch portgroup providing network connectivity."
}

variable "vcenter_folder" {
  type        = string
  description = "Target virtual machine inventory folder for template organization."
  default     = ""
}

variable "iso_paths" {
  type        = list(string)
  description = "List containing the datastore path to the Rocky Linux 9 minimal ISO image."
}

variable "vm_name" {
  type        = string
  description = "Name assigned to the virtual machine during build and converted template."
}

variable "vm_cpu_cores" {
  type        = number
  description = "Number of virtual CPU cores allocated."
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
  description = "Flag enabling thin disk provisioning format."
  default     = true
}

variable "ssh_username" {
  type        = string
  description = "Default administrative username created via Kickstart."
}

variable "ssh_password" {
  type        = string
  description = "Password for the administrative user to establish SSH connectivity."
  sensitive   = true
}

variable "ssh_password_hash" {
  type        = string
  description = "SHA-512 encrypted password hash for Anaconda kickstart user creation."
  sensitive   = true
  default     = ""
}

variable "ssh_public_key" {
  type        = string
  description = "Optional SSH public key installed for the administrative user."
  sensitive   = true
  default     = ""
}

variable "ssh_timeout" {
  type        = string
  description = "Maximum duration Packer waits for SSH service availability before terminating."
  default     = "30m"
}

variable "additional_packages" {
  type        = list(string)
  description = "Additional RPM package names installed during Kickstart."
  default     = []
}
