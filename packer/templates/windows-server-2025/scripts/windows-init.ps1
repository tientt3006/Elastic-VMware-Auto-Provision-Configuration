# ==============================================================================
# Initial WinRM Configuration & Firewall Adjustment for Packer Communicator
# Reference: Broadcom packer-examples-for-vsphere
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Output "Setting the network connection profiles to Private..."
$connectionProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue
$attempts = 0
While (($null -eq $connectionProfile -or $connectionProfile.Name -eq 'Identifying...') -and $attempts -lt 12) {
    Start-Sleep -Seconds 5
    $connectionProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    $attempts++
}

# Ensure all connection profiles are Private to allow WinRM quickconfig
Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
    Set-NetConnectionProfile -Name $_.Name -NetworkCategory Private -ErrorAction SilentlyContinue
}

Write-Output "Configuring Windows Remote Management (WinRM)..."
winrm quickconfig -quiet
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

Write-Output "Configuring Windows Firewall for WinRM..."
netsh advfirewall firewall set rule group="Windows Remote Administration" new enable=yes
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes action=allow

# Reset AutoLogon count to prevent continuous auto-logon loops
Write-Output "Resetting AutoLogon count..."
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoLogonCount -Value 0 -ErrorAction SilentlyContinue

Write-Output "WinRM initial configuration complete."
