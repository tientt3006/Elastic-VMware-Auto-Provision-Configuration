# ==============================================================================
# Initial WinRM Configuration & Firewall Adjustment for Packer Communicator
# Reference: Broadcom packer-examples-for-vsphere
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Output "Configuring Network Connection Profile to Private..."
$maxAttempts = 12
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $profiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($profiles -and ($profiles | Where-Object { $_.IPv4Connectivity -ne "NoTraffic" })) {
        foreach ($p in $profiles) {
            Set-NetConnectionProfile -Name $p.Name -NetworkCategory Private -ErrorAction SilentlyContinue
        }
        break
    }
    Start-Sleep -Seconds 5
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
