output "folders" {
  description = "Map of created folders with their IDs and paths."
  value = {
    for name, f in vsphere_folder.vm_folders : name => {
      id   = f.id
      path = f.path
    }
  }
}

output "folder_paths" {
  description = "Map of folder names to their inventory paths."
  value       = { for name, f in vsphere_folder.vm_folders : name => f.path }
}
