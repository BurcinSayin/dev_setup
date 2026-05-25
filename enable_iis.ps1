# Run as Administrator

# Ensure running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires Administrator privileges. Relaunching elevated..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

$urlRewriteId = 'Microsoft.IIS.URLRewrite'

function Read-FeatureList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Feature list not found: $Path" -ForegroundColor Red
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

$features = Read-FeatureList -Path (Join-Path $PSScriptRoot 'iis_features.json')

Write-Host "Enabling IIS optional features..." -ForegroundColor Green
$rebootRequired = $false

foreach ($name in $features) {
    Write-Host "Enabling $name..." -ForegroundColor Cyan
    try {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) {
            $rebootRequired = $true
        }
    }
    catch {
        Write-Host "  Failed to enable ${name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Installing URL Rewrite module ($urlRewriteId)..." -ForegroundColor Cyan
winget install --id $urlRewriteId --scope machine --accept-package-agreements --accept-source-agreements

Write-Host ""
if ($rebootRequired) {
    Write-Host "==========================================================================" -ForegroundColor Yellow
    Write-Host " A REBOOT IS REQUIRED before IIS is fully operational." -ForegroundColor Yellow
    Write-Host " 'iisreset' is NOT sufficient for features pending enablement." -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Yellow
}
else {
    Write-Host "Done. No reboot reported as required." -ForegroundColor Green
}
