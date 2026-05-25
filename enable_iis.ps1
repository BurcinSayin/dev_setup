# Run as Administrator
param(
    [switch]$Install
)

# Ensure running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires Administrator privileges. Relaunching elevated..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($Install.IsPresent) {
        $argList += "-Install"
    }
    if ($args) {
        $argList += $args
    }
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

$runInstall = $Install.IsPresent -or ($args -contains '--install') -or ($args -contains '-Install')

$urlRewriteId = 'Microsoft.IIS.URLRewrite'
$urlRewriteSchema = Join-Path $env:windir 'System32\inetsrv\rewrite_schema.xml'

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

function Get-FeatureState {
    param([string]$Name)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        return $f.State.ToString()
    }
    catch {
        return 'Unknown'
    }
}

if ($runInstall) {
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
}
else {
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                       IIS / ASP.NET 4.8 Status                          " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Querying Windows optional features (this might take a moment)..." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host ("{0,-40} {1,-15}" -f "Feature / Module", "State") -ForegroundColor White
    Write-Host ("{0,-40} {1,-15}" -f "----------------", "-----") -ForegroundColor DarkGray

    foreach ($name in $features) {
        $state = Get-FeatureState -Name $name
        switch ($state) {
            'Enabled'  { $color = 'Green' }
            'Disabled' { $color = 'Yellow' }
            default    { $color = 'Red' }
        }
        Write-Host ("{0,-40} " -f $name) -NoNewline
        Write-Host ("[{0}]" -f $state) -ForegroundColor $color
    }

    $rewriteInstalled = Test-Path -LiteralPath $urlRewriteSchema
    $rewriteState = if ($rewriteInstalled) { 'Installed' } else { 'Missing' }
    $rewriteColor = if ($rewriteInstalled) { 'Green' } else { 'Yellow' }
    Write-Host ("{0,-40} " -f "$urlRewriteId (URL Rewrite)") -NoNewline
    Write-Host ("[{0}]" -f $rewriteState) -ForegroundColor $rewriteColor

    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Hint: To enable everything, run: .\enable_iis.ps1 --install" -ForegroundColor Gray
}
