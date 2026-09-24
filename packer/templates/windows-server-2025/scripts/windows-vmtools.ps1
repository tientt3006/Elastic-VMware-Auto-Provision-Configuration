# ==============================================================================
# Silent Installation and Verification of VMware Tools
# Reference: Broadcom packer-examples-for-vsphere
# ==============================================================================
param (
    [string]$SetupPath = "E:",
    [int]$MaxRetries = 15,
    [int]$RetryInterval = 3
)

$ErrorActionPreference = "Stop"
$VMToolsName = "VMware Tools"
$VMToolsServiceName = "VMTools"

# 1. Resolve SetupPath: If E:\ does not contain setup64.exe, scan drives D: to Z:
if (-not (Test-Path "$SetupPath\setup64.exe")) {
    Write-Output "setup64.exe not found on default drive $SetupPath. Searching drives D: to Z:..."
    foreach ($letter in [char[]](68..90)) {
        $candidate = "$([string]$letter):"
        if (Test-Path "$candidate\setup64.exe") {
            $SetupPath = $candidate
            Write-Output "Found VMware Tools installer on drive: $SetupPath"
            break
        }
    }
}

Function Get-VMToolsInstall {
    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($path in $registryPaths) {
        try {
            if (Get-ChildItem $path -ErrorAction Stop | Where-Object { $_.GetValue("DisplayName") -like "*$VMToolsName*" }) {
                return $true
            }
        } catch {
            Write-Warning ("Failed to access registry path: {0}. {1}" -f $path, $_)
        }
    }
    return $false
}

Function Get-VMToolsService {
    param (
        [int]$MaxRetries,
        [int]$RetryInterval
    )

    Write-Output "Checking $VMToolsName service status..."
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        Start-Sleep -Seconds $RetryInterval
        try {
            $Service = Get-Service $VMToolsServiceName -ErrorAction SilentlyContinue
            if ($Service -and $Service.Status -eq "Running") {
                Write-Output "$VMToolsName service is in a running state."
                return $true
            }
        } catch {
            Write-Warning ("Failed to get service status: {0}" -f $_)
        }
    }
    return $false
}

Function Install-VMTools {
    param (
        [string]$SetupPath,
        [string]$Arguments
    )

    $setupFile = ""
    if (Test-Path "$SetupPath\setup64.exe") {
        $setupFile = "$SetupPath\setup64.exe"
    } elseif ((Test-Path "$SetupPath\setup.exe") -and (Test-Path "$SetupPath\VMware")) {
        $setupFile = "$SetupPath\setup.exe"
    } else {
        Write-Error "Neither setup64.exe nor VMware Tools setup.exe found in $SetupPath"
        return $false
    }

    Write-Output "Installing $VMToolsName using $setupFile..."
    try {
        Start-Process -FilePath $setupFile -ArgumentList $Arguments -Wait
        return $true
    } catch {
        Write-Error ("Failed to install {0}: {1}" -f $VMToolsName, $_)
        return $false
    }
}

# Check if VMware Tools is already installed
$vmToolsInstalled = Get-VMToolsInstall

if ($vmToolsInstalled) {
    if (Get-VMToolsService -MaxRetries $MaxRetries -RetryInterval $RetryInterval) {
        Write-Output "$VMToolsName is already installed and running."
        exit 0
    }
}

Write-Output "Proceeding with VMware Tools installation from $SetupPath..."
if (-not (Install-VMTools -SetupPath $SetupPath -Arguments '/s /v "/qb REBOOT=R"')) {
    Write-Warning "Failed to install $VMToolsName from $SetupPath"
} else {
    Write-Output "$VMToolsName installer completed."
}

if (-not (Get-VMToolsService -MaxRetries $MaxRetries -RetryInterval $RetryInterval)) {
    Write-Warning "$VMToolsName service is not running yet."
} else {
    Write-Output "$VMToolsName service is running and active."
}
