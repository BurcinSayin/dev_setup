# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Single-script Windows dev-environment bootstrapper. `win_installs.ps1` declares two lists of `winget` package IDs and either reports their install status or installs them.

## Commands

- Show install status of all declared packages (default, no install):
  `.\win_installs.ps1`
- Install everything:
  `.\win_installs.ps1 --install` (or `-Install`)

Both invocations self-elevate via `Start-Process -Verb RunAs` if not already running as Administrator, so they must be launched from an interactive PowerShell session (the UAC prompt will appear).

## Architecture

Two JSON files in the same directory as the script drive everything — flat arrays of `winget` IDs:

- `machine_apps.json` — installed with `--scope machine` (system-wide, requires admin).
- `user_apps.json` — installed with `--scope user` (per-user profile). Some IDs here are Microsoft Store IDs (e.g. `9NK4T08DHQ80` for Dropbox) rather than winget package names.

`win_installs.ps1` loads both via `Read-PackageList` (which exits with a clear error if a file is missing or malformed) and resolves them with `$PSScriptRoot`, so the script must live alongside its JSON.

A package can legitimately appear in both lists when it ships separate machine and user installers (e.g. Postman). The status report probes each scope independently with `winget list --exact --scope <machine|user>` and reports `Machine`, `User`, `Machine & User`, or `Missing`.

## When adding packages

- Edit the JSON files, not the script. Look up the exact winget ID with `winget search <name>` first — IDs are case-sensitive on some sources and a wrong ID silently fails the install loop without aborting.
- Put it in `machine_apps.json` unless the package only supports per-user install or is a Store ID.
