# Run as Administrator

# Ensure running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires Administrator privileges. Relaunching elevated..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

function Read-PackageList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Package list not found: $Path" -ForegroundColor Red
        exit 1
    }
    try {
        $items = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Failed to parse JSON in ${Path}: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    return @($items | Where-Object { $_ -and $_.Trim() -ne "" })
}

$machine_packages = Read-PackageList -Path (Join-Path $PSScriptRoot 'machine_apps.json')
$user_packages    = Read-PackageList -Path (Join-Path $PSScriptRoot 'user_apps.json')

Write-Host "Starting installations..." -ForegroundColor Green

foreach ($id in $machine_packages) {
    if ($id -and $id.Trim() -ne "") {
        Write-Host "Installing $id (Machine scope)..." -ForegroundColor Cyan
        winget install --id $id --scope machine --accept-package-agreements --accept-source-agreements
    }
}

foreach ($id in $user_packages) {
    if ($id -and $id.Trim() -ne "") {
        Write-Host "Installing $id (User scope)..." -ForegroundColor Cyan
        winget install --id $id --scope user --accept-package-agreements --accept-source-agreements
    }
}
