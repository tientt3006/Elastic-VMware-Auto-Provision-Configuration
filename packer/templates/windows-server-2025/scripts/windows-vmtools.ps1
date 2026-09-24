# ==============================================================================
# Silent Installation and Verification of VMware Tools
# Designed for automated Packer Golden Image Pipeline
# ==============================================================================
$ErrorActionPreference = "Stop"

Write-Output "Detecting VMware Tools media..."

# Find drive containing setup64.exe (standard for 64-bit Windows guest)
$toolsDrive = (Get-Volume | Where-Object { 
    $_.DriveLetter -and (Test-Path ($_.DriveLetter + ":\setup64.exe")) 
} | Select-Object -First 1).DriveLetter

# Fallback: check setup.exe ONLY if the volume is verified to be VMware Tools (never Windows Setup ISO)
if (-not $toolsDrive) {
    $toolsDrive = (Get-Volume | Where-Object { 
        $_.DriveLetter -and `
        (Test-Path ($_.DriveLetter + ":\setup.exe")) -and `
        ((Test-Path ($_.DriveLetter + ":\VMware")) -or ($_.FileSystemLabel -match "VMware"))
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
} else {
    Write-Warning "VMware Tools installer CD-ROM (setup64.exe) not found. Skipping VMware Tools installation."
}
