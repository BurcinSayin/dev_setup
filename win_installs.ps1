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

if ($runInstall) {
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
}
else {
    $all_packages = ($machine_packages + $user_packages) | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique
    $throttle = 8

    $useThreadJob = [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
    if (-not $useThreadJob) {
        try {
            Install-Module -Name ThreadJob -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Import-Module ThreadJob -ErrorAction Stop
            $useThreadJob = [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
        }
        catch {
            $useThreadJob = $false
        }
    }

    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                      Package Installation Status                         " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    $checkCount = $all_packages.Count * 2
    Write-Host ("Scanning system packages with winget (running {0} checks, up to {1} in parallel)..." -f $checkCount, $throttle) -ForegroundColor DarkGray
    if (-not $useThreadJob) {
        Write-Host "ThreadJob module unavailable; falling back to Start-Job (slower startup)." -ForegroundColor Yellow
    }
    Write-Host ""

    $work = foreach ($id in $all_packages) {
        [pscustomobject]@{ Id = $id; Scope = 'machine' }
        [pscustomobject]@{ Id = $id; Scope = 'user' }
    }

    $jobScript = {
        param($id, $scope)
        winget list --id $id --exact --scope $scope *> $null
        [pscustomobject]@{ Id = $id; Scope = $scope; Found = ($LASTEXITCODE -eq 0) }
    }

    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($item in $work) {
        while (@(Get-Job -State Running).Count -ge $throttle) {
            Start-Sleep -Milliseconds 50
        }
        if ($useThreadJob) {
            $job = Start-ThreadJob -ScriptBlock $jobScript -ArgumentList $item.Id, $item.Scope
        }
        else {
            $job = Start-Job -ScriptBlock $jobScript -ArgumentList $item.Id, $item.Scope
        }
        $jobs.Add($job)
    }

    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force

    $installedMachine = @{}
    $installedUser = @{}
    foreach ($r in $results) {
        if (-not $r.Found) { continue }
        if ($r.Scope -eq 'machine') { $installedMachine[$r.Id] = $true }
        elseif ($r.Scope -eq 'user') { $installedUser[$r.Id] = $true }
    }

    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "Package ID", "Installed Scope", "Status") -ForegroundColor White
    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "----------", "---------------", "------") -ForegroundColor DarkGray

    foreach ($id in $all_packages) {
        $isMachine = $installedMachine.ContainsKey($id)
        $isUser = $installedUser.ContainsKey($id)

        if ($isMachine -and $isUser) {
            $actualScope = "Machine & User"
            $status = "Installed"
            $statusColor = "Green"
        }
        elseif ($isMachine) {
            $actualScope = "Machine"
            $status = "Installed"
            $statusColor = "Green"
        }
        elseif ($isUser) {
            $actualScope = "User"
            $status = "Installed"
            $statusColor = "Green"
        }
        else {
            $actualScope = "-"
            $status = "Missing"
            $statusColor = "Yellow"
        }

        Write-Host ("{0,-40} " -f $id) -NoNewline
        Write-Host ("{0,-18} " -f $actualScope) -NoNewline
        Write-Host ("[{0}]" -f $status) -ForegroundColor $statusColor
    }
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Hint: To install missing packages, run: .\win_installs.ps1 --install" -ForegroundColor Gray
}