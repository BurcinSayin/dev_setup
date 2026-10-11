
Enable scripts first

Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

Run this in the PowerShell version you normally use to create and open its current profile:


New-Item -ItemType Directory -Path (Split-Path $PROFILE) -Force | Out-Null
if (!(Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE | Out-Null
}
notepad $PROFILE

Add this line at the bottom, then save:

fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression




**CMD supports fnm, 

1. Open **CMD** and create a startup file:

```bat
notepad "%USERPROFILE%\fnm-init.cmd"
```

Paste this into Notepad and save:

```bat
@echo off
if not defined FNM_AUTORUN_GUARD (
    set "FNM_AUTORUN_GUARD=AutorunGuard"
    FOR /f "tokens=*" %%z IN ('fnm env --use-on-cd') DO CALL %%z
)
```

2. Check whether CMD already has a startup command:

```bat
reg query "HKCU\Software\Microsoft\Command Processor" /v AutoRun
```

**If it reports that the value cannot be found**, register your script:

```bat
reg add "HKCU\Software\Microsoft\Command Processor" /v AutoRun /t REG_SZ /d "call C:\Users\burci\fnm-init.cmd" /f
```

If an AutoRun value already exists, preserve it—share its output so the fnm initialization can be appended correctly.

3. Open a new CMD window and test:

```bat
fnm use 24
node --version
npm --version
```

IDEs that launch CMD with `/d` disable AutoRun, so those terminals need explicit startup configuration.


