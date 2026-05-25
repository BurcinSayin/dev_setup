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

Two package lists drive everything:

- `$machine_packages` (win_installs.ps1:23) — installed with `--scope machine` (system-wide, requires admin).
- `$user_packages` (win_installs.ps1:41) — installed with `--scope user` (per-user profile). Some IDs here are Microsoft Store IDs (e.g. `9NK4T08DHQ80` for Dropbox) rather than winget package names.

A package can legitimately appear in both lists when it ships separate machine and user installers (e.g. Postman). The status report (win_installs.ps1:80) probes each scope independently with `winget list --exact --scope <machine|user>` and reports `Machine`, `User`, `Machine & User`, or `Missing`.

## Known issue

Line 74 references `$packages`, which is never defined. The `$all_packages` union still works because PowerShell treats undefined variables as `$null` and the `Where-Object` filter drops it, but the reference is dead and should either be removed or replaced with a real third list.

## When adding packages

- Look up the exact winget ID with `winget search <name>` before adding — IDs are case-sensitive on some sources and a wrong ID silently fails the install loop without aborting.
- Put it in `$machine_packages` unless the package only supports per-user install or is a Store ID.
