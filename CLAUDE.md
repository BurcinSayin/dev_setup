# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Windows 11 dev-environment bootstrappers. Two sibling scripts, both JSON-driven and following the same self-elevate / status-by-default / `--install` convention:

- `win_installs.ps1` — installs winget packages declared in `machine_apps.json` and `user_apps.json`.
- `enable_iis.ps1` — enables the IIS optional features in `iis_features.json` for hosting ASP.NET 4.8 apps, and installs the URL Rewrite IIS module via winget.

## Commands

- Show status (default, no changes):
  `.\win_installs.ps1` / `.\enable_iis.ps1`
- Apply changes:
  `.\win_installs.ps1 --install` / `.\enable_iis.ps1 --install` (each also accepts `-Install`)

Both scripts self-elevate via `Start-Process -Verb RunAs` if not already Administrator, so they must be launched from an interactive PowerShell session (UAC prompt appears).

## Architecture

JSON files in the same directory as the scripts drive everything — flat arrays of identifiers, loaded via `$PSScriptRoot` so the script must live alongside its JSON:

- `machine_apps.json` — winget IDs installed with `--scope machine` (system-wide).
- `user_apps.json` — winget IDs installed with `--scope user`. Some IDs are Microsoft Store IDs (e.g. `9NK4T08DHQ80` for Dropbox) rather than winget package names.
- `iis_features.json` — DISM feature names enabled via `Enable-WindowsOptionalFeature`. `IIS-ASPNET45` covers ASP.NET 4.5 through 4.8.

`win_installs.ps1` loads its lists via `Read-PackageList`; `enable_iis.ps1` uses an identically-shaped `Read-FeatureList`. Both exit with a clear error if a file is missing or malformed.

A winget package can legitimately appear in both `machine_apps.json` and `user_apps.json` when it ships separate installers (e.g. Postman). `win_installs.ps1`'s status report probes each scope independently in parallel via `Start-ThreadJob` (with a `Start-Job` fallback if the `ThreadJob` module is missing) and reports `Machine`, `User`, `Machine & User`, or `Missing`. `enable_iis.ps1`'s status report uses `Get-WindowsOptionalFeature` per feature and probes `%windir%\System32\inetsrv\rewrite_schema.xml` to detect URL Rewrite.

After `enable_iis.ps1 --install`, a full reboot is typically required before IIS is operational — `iisreset` is not sufficient for DISM features that report `RestartNeeded`. The script prints a yellow warning in that case.

## When adding packages or features

- Edit the JSON files, not the scripts. Look up exact winget IDs with `winget search <name>` first — IDs are case-sensitive on some sources and a wrong ID silently fails the install loop without aborting.
- Put winget IDs in `machine_apps.json` unless the package only supports per-user install or is a Store ID.
- Look up DISM feature names with `Get-WindowsOptionalFeature -Online | Where-Object FeatureName -like 'IIS-*'` before adding to `iis_features.json`.
