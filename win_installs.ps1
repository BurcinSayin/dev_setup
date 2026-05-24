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

$machine_packages = @(
    "Git.Git"                       # Version control
    "GitHub.cli"                    # gh CLI
    "7zip.7zip"                     # Archiver
    "curl.curl"                     # HTTP client
    "JernejSimoncic.Wget"           # wget
    "jqlang.jq"                     # JSON processor
    "Postman.Postman"               # API testing
    "Amazon.AWSCLI"                 # aws CLI
    "Notepad++.Notepad++"
    "Mozilla.Firefox.DeveloperEdition"
    "Schniz.fnm"
    "mRemoteNG.mRemoteNG"
    "pCloudAG.pCloudDrive"
)

$user_packages = @(
    "Postman.Postman"               # API testing
    "9NK4T08DHQ80"               # Dropbox
    "JetBrains.Toolbox"
    "Google.AntigravityIDE"
)

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
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                      Package Installation Status                         " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Scanning system packages with winget (this might take a minute)..." -ForegroundColor DarkGray
    Write-Host ""
    
    # Combine all packages uniquely
    $all_packages = ($machine_packages + $user_packages + $packages) | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique
    
    # Print header
    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "Package ID", "Installed Scope", "Status") -ForegroundColor White
    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "----------", "---------------", "------") -ForegroundColor DarkGray
    
    foreach ($id in $all_packages) {
        # Test Machine scope (Silently drop stdout/stderr)
        winget list --id $id --exact --scope machine *> $null
        $isMachine = ($LASTEXITCODE -eq 0)

        # Test User scope (Silently drop stdout/stderr)
        winget list --id $id --exact --scope user *> $null
        $isUser = ($LASTEXITCODE -eq 0)
        
        # Determine actual scope
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