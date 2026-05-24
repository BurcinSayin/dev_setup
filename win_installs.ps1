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
)

$packages = @(
    "Postman.Postman"               # API testing
    "JetBrains.Toolbox"
    "Google.AntigravityIDE"
    "pCloudAG.pCloudDrive"
)

$user_packages = @(
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

    foreach ($id in $packages) {
        if ($id -and $id.Trim() -ne "") {
            Write-Host "Installing $id (User scope)..." -ForegroundColor Cyan
            winget install --id $id --accept-package-agreements --accept-source-agreements
        }
    }
}
else {
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "                      Package Installation Status                         " -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Scanning system packages with winget (this may take a few seconds)..." -ForegroundColor DarkGray
    
    # Fetch winget outputs once
    $machineOutput = winget list --scope machine 2>$null | Out-String
    $userOutput = winget list --scope user 2>$null | Out-String
    
    Write-Host "Scan complete!`n" -ForegroundColor Green
    
    # Combine all packages uniquely
    $all_packages = ($machine_packages + $user_packages + $packages) | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique
    
    # Print header
    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "Package ID", "Installed Scope", "Status") -ForegroundColor White
    Write-Host ("{0,-40} {1,-18} {2,-15}" -f "----------", "---------------", "------") -ForegroundColor DarkGray
    
    foreach ($id in $all_packages) {
        $idEscaped = [regex]::Escape($id)
        $isMachine = $machineOutput -match "\b$idEscaped\b"
        $isUser = $userOutput -match "\b$idEscaped\b"
        
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