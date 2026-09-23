# ==============================================================================
# Silent Installation and Verification of VMware Tools
# Designed for automated Packer Golden Image Pipeline
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Output "Detecting VMware Tools media..."

# Find drive containing setup64.exe
$toolsDrive = (Get-Volume | Where-Object { 
    $_.DriveLetter -and (Test-Path ($_.DriveLetter + ":\setup64.exe")) 
} | Select-Object -First 1).DriveLetter

if (-not $toolsDrive) {
    Write-Warning "setup64.exe not found on root of any drive. Searching for setup.exe..."
    $toolsDrive = (Get-Volume | Where-Object { 
        $_.DriveLetter -and (Test-Path ($_.DriveLetter + ":\setup.exe")) 
    } | Select-Object -First 1).DriveLetter
}

if ($toolsDrive) {
    $installerPath = $toolsDrive + ":\setup64.exe"
    if (-not (Test-Path $installerPath)) {
        $installerPath = $toolsDrive + ":\setup.exe"
    }
    Write-Output "Installing VMware Tools from: $installerPath"
    $proc = Start-Process -FilePath $installerPath -ArgumentList '/s /v "/qn REBOOT=R"' -Wait -PassThru
    Write-Output "Installer process exited with code: $($proc.ExitCode)"
} else {
    Write-Warning "Could not find VMware Tools installer CD-ROM. Relying on pre-installed drivers."
}

# Wait and verify VMTools service
$serviceName = "VMTools"
$maxRetries = 15
$serviceRunning = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Write-Output "VMware Tools service ($serviceName) is active and running."
        $serviceRunning = $true
        break
    }
    Write-Output "Waiting for $serviceName service to start (attempt $i/$maxRetries)..."
    Start-Sleep -Seconds 3
}

if (-not $serviceRunning) {
    Write-Warning "VMTools service is not running yet. Windows will continue to boot."
}
