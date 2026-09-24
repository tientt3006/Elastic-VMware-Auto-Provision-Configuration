# ==============================================================================
# Windows Server 2025 Golden Template Hardening & Generalization Script
# Executed via Packer PowerShell provisioner over WinRM
# ==============================================================================
$ErrorActionPreference = "Continue"

Write-Output "--- [1/5] Enabling Remote Desktop Protocol (RDP) ---"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

Write-Output "--- [2/5] Configuring High Performance Power Management ---"
powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg.exe /change monitor-timeout-ac 0 2>$null
powercfg.exe /change disk-timeout-ac 0 2>$null
powercfg.exe /change standby-timeout-ac 0 2>$null
powercfg.exe /hibernate off 2>$null

Write-Output "--- [3/5] Disabling Local Administrator Password Expiration ---"
Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue | Set-LocalUser -PasswordNeverExpires $true

Write-Output "--- [4/5] Enforcing TLS 1.2 and TLS 1.3 Security Standards ---"
$protocols = @("TLS 1.2", "TLS 1.3")
foreach ($proto in $protocols) {
    $clientPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\Client"
    $serverPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\Server"
    New-Item -Path $clientPath -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $serverPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $clientPath -Name "Enabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $clientPath -Name "DisabledByDefault" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $serverPath -Name "Enabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $serverPath -Name "DisabledByDefault" -Value 0 -Type DWord -Force
}

Write-Output "--- [5/5] Cleaning Up Temporary Files and Setup Logs ---"
$cleanupPaths = @(
    "$env:TEMP\*",
    "$env:WINDIR\Panther\*",
    "$env:WINDIR\SoftwareDistribution\Download\*"
)
foreach ($path in $cleanupPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path "$env:WINDIR\Temp" -Exclude "packer-*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "Windows Server 2025 Golden Template preparation complete."
