# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Dev-environment bootstrappers for two OS families. Each OS lives in its own folder with its own native scripts and JSON manifests — there is no shared execution code and no cross-platform runtime dependency.

- `windows/` — Windows 11. Self-elevating PowerShell over winget and DISM.
- `ubuntu/` — Ubuntu 24.04 LTS or newer. Self-elevating bash over apt.

## Commands

Run any script with no arguments to apply changes:

| OS | Command | Effect |
|---|---|---|
| Windows | `.\windows\win_installs.ps1` | Installs the winget packages in `machine_apps.json` + `user_apps.json` |
| Windows | `.\windows\enable_iis.ps1` | Enables the IIS features in `iis_features.json`, installs URL Rewrite |
| Ubuntu | `./ubuntu/ubuntu_installs.sh` | Installs the apt packages in `apt_packages.json`, then nvm + current Node LTS + the npm globals in `npm_packages.json` for the invoking user |

All three self-elevate — the PowerShell scripts via `Start-Process -Verb RunAs`, the bash script via `exec sudo`. Do **not** prefix the Ubuntu script with `sudo`; it re-executes itself. The PowerShell scripts must be launched from an interactive session (a UAC prompt appears).

Both package managers are idempotent, so re-running skips what is already installed.

## Architecture

JSON manifests drive everything. Each script resolves its manifests as **siblings of itself** — `$PSScriptRoot` in PowerShell, `SCRIPT_DIR` in bash — so a script and its JSON must stay in the same folder. Moving a script without its manifests breaks it.

### Windows (`windows/`)

- `machine_apps.json` — winget IDs installed with `--scope machine` (system-wide).
- `user_apps.json` — winget IDs installed with `--scope user`. Some entries are Microsoft Store IDs (e.g. `9NK4T08DHQ80` for Dropbox) rather than winget package names.
- `iis_features.json` — DISM feature names enabled via `Enable-WindowsOptionalFeature`. `IIS-ASPNET45` covers ASP.NET 4.5 through 4.8.

`win_installs.ps1` loads its lists via `Read-PackageList`; `enable_iis.ps1` uses an identically-shaped `Read-FeatureList`. Both exit with a clear error if a file is missing or malformed.

A winget package can legitimately appear in both `machine_apps.json` and `user_apps.json` when it ships separate installers (e.g. Postman) — each scope is installed independently.

After `enable_iis.ps1` runs, a full reboot is typically required before IIS is operational — `iisreset` is not sufficient for DISM features that report `RestartNeeded`. The script prints a yellow warning in that case.

### Ubuntu (`ubuntu/`)

- `apt_packages.json` — flat array of apt package names, same shape as the Windows manifests.
- `npm_packages.json` — flat array of npm packages installed globally **for the invoking user**, not root. See the user phase below.
- `apt_repos.json` — **the one exception to the flat-array rule.** An array of objects, shipped empty (`[]`) with its registration loop wired and idle. It exists so a future vendor repo can be added without reshaping the script:

  ```json
  {
    "name": "docker",
    "key_url": "https://download.docker.com/linux/ubuntu/gpg",
    "source_line": "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable"
  }
  ```

  Each entry writes its key to `/etc/apt/keyrings/<name>.asc` and its source line to `/etc/apt/sources.list.d/<name>.list`, then triggers one `apt-get update` if anything was newly added. Already-registered repos are skipped.

`ubuntu_installs.sh` bootstraps `jq` and `curl` before reading the manifests — `jq` is the parser and `curl` fetches repo keys, and both are also listed in `apt_packages.json`. That is intentional, not a duplicate: apt is idempotent and the install loop simply reports them as already present.

`.gitattributes` pins `*.sh` to LF. The scripts are authored on Windows; a CRLF shebang yields `bad interpreter: /usr/bin/env bash^M` on Linux.

### The two-phase privilege model

`ubuntu_installs.sh` runs in two phases with **different privileges**:

1. **Root phase** — apt work. The script self-elevates, exactly as before.
2. **User phase** — nvm, Node and global npm packages. These must not be owned by root, so the script drops back down with `sudo -u "$TARGET_USER" -H`.

`-H` is **mandatory**. Without it `HOME` stays `/root`, and nvm installs into `/root/.nvm` while owned by the wrong user — a silent, confusing failure.

The user phase is a **single heredoc**, and must stay that way. `nvm` is a shell function, not a binary; it only exists in the shell that sourced `nvm.sh`. Splitting the phase into several `sudo -u` calls would lose `nvm` between them. Values cross the boundary as positional arguments (`bash -s -- "$a" "$b"`) rather than environment variables, so a strict `sudoers` env policy cannot strip them.

Target user resolution is `DEV_SETUP_USER` → `SUDO_USER`. The phase is **skipped with a warning**, never silently redirected to `/root`, when:

- `SUDO_USER` is unset (the script was launched from a real root shell),
- it resolves to `root` without an explicit `DEV_SETUP_USER` opt-in, or
- the named user does not exist.

Set `DEV_SETUP_USER=<name>` to run the phase for a specific account — including `root`, if that is genuinely wanted.

### Node and Claude Code

`NVM_VERSION` and `NODE_VERSION` are **script constants, not manifest entries**, following the `$urlRewriteId` precedent in `enable_iis.ps1`. nvm is pinned to a tag rather than `master` so the fetched installer is deterministic; keep it at `v0.40.5` or later, which carries the fix for CVE-2026-10796.

`NODE_VERSION='--lts'` resolves the current LTS at install time rather than hardcoding a major — Node 24 "Krypton" today, Node 26 automatically once it promotes in October 2026. Set a major like `'22'` to pin instead.

`nodejs` and `npm` are **deliberately absent from `apt_packages.json`.** Installing them would put a second Node on `PATH` competing with nvm's. Node and npm come from nvm alone.

Claude Code installs via `npm install -g` inside the user phase. It does not use Node at runtime — the npm package just delivers a native binary, and it bundles its own ripgrep. `ripgrep` is in the apt list as insurance (so `USE_BUILTIN_RIPGREP=0` is available) rather than as a hard requirement.

One consequence worth knowing: nvm's Node lives only in **interactive shells**, because it is sourced from `~/.bashrc`. Root, `cron`, and `systemd` units will not see `node`. If a service ever needs Node, that requires a system-wide install (a NodeSource `apt_repos.json` entry), not nvm.

Anthropic also publishes a signed apt repo for Claude Code (`downloads.claude.ai/claude-code/apt/stable`, key fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`). It was evaluated and not chosen — npm-under-nvm was preferred — but it is the obvious `apt_repos.json` entry if the npm route is ever dropped.

## Platform boundaries

`enable_iis.ps1` is **Windows-only by construction, not by oversight.** `iis_features.json` targets `IIS-ASPNET45` for hosting ASP.NET 4.8, and ASP.NET 4.8 is .NET Framework, which does not run on Linux at all — only .NET Core / .NET 5+ does. There is no like-for-like Ubuntu port and there should not be one.

Linux hosting (modern .NET plus a reverse proxy) is **deferred, not cancelled**. When it is wanted, it attaches as a new `ubuntu/` provisioning script, with `apt_repos.json` as the mechanism for registering the Microsoft package repo. No restructuring required.

Ubuntu scope is currently a minimal shared core of CLI tools. GUI applications, and Windows-only apps with no apt equivalent, are deliberately out of scope — the Ubuntu manifest is not meant to mirror the Windows one.

## Ubuntu version target

Pinned to **24.04 LTS or newer**. All current packages come from the default repos on 24.04 with `universe` enabled (the default on Desktop and Server). Two things differ on 22.04 and earlier, which is why the pin exists:

- `gh` is not packaged; it needs the `cli.github.com` apt repo (an `apt_repos.json` entry).
- 7-Zip is `p7zip-full`, not `7zip`. On 24.04 `p7zip-full` is only a transitional package.

## When adding packages or features

- Edit the JSON files, not the scripts.
- **Windows:** look up exact winget IDs with `winget search <name>` first. IDs are case-sensitive on some sources, and a wrong ID silently fails the install loop without aborting.
- **Ubuntu:** verify names with `apt-cache policy <name>` first — a wrong name fails the same non-aborting way. The script reports failed packages in a red summary and exits non-zero, so a bad name is visible at the end even though it does not stop the run.
- Put winget IDs in `machine_apps.json` unless the package only supports per-user install or is a Store ID.
- Look up DISM feature names with `Get-WindowsOptionalFeature -Online | Where-Object FeatureName -like 'IIS-*'` before adding to `iis_features.json`.
- Prefer a default-repo apt package over an `apt_repos.json` entry. Adding a vendor repo is a real maintenance cost and should be justified.
- **npm globals:** add to `npm_packages.json` only what genuinely belongs in the user's global scope — CLI tools, not project dependencies. Check the name with `npm view <name> version` first. These install under nvm's prefix as the invoking user; never add a step that runs `npm install -g` under sudo.

## Install sources

Ubuntu draws from three lanes, in order of preference:

1. **apt** — the default for anything system-wide, from Ubuntu's own repos where possible.
2. **npm globals under nvm** — user-scoped CLI tools, via `npm_packages.json`.
3. **A single sanctioned `curl | bash`** — the nvm bootstrap, and nothing else.

That third lane is a deliberate, narrow exception. nvm publishes no apt package, so there is no alternative. It is pinned to a version tag rather than `master` to keep the fetched script deterministic. Do not widen this lane to other tools without a comparable justification: prefer apt, then a vendor apt repo via `apt_repos.json`, and treat piping a remote script to a shell as the last resort.
