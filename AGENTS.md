# Repository Guidelines

## Project Overview

Dev-environment provisioning for Windows 11 and Ubuntu 24.04 LTS or newer. Native PowerShell and Bash scripts install packages and configure platform features from JSON manifests. This is not a shared application or cross-platform runtime. Auxiliary utilities and manual setup notes are independent of the installers.

## Architecture & Data Flow

- **Manifest-driven entry points:** scripts resolve JSON beside themselves using `$PSScriptRoot` on Windows and `SCRIPT_DIR` on Ubuntu. Keep scripts and their manifests together; change package selections in JSON, not installation loops.
- **Windows packages:** `win_installs.ps1` self-elevates through UAC, reads machine/user lists, and invokes winget with the matching scope. It relies on winget's installed-package behavior rather than pre-checks.
- **Windows IIS:** `enable_iis.ps1` self-elevates, enables DISM features, installs URL Rewrite, and warns when a reboot is required. IIS/ASP.NET Framework hosting is Windows-only; do not create a like-for-like Linux port.
- **Ubuntu root phase:** self-reexecutes through sudo, refreshes apt indexes, bootstraps jq/curl, validates manifests, registers optional repositories, then installs missing apt packages.
- **Ubuntu user phase:** resolves `DEV_SETUP_USER` before `SUDO_USER`, then runs one `sudo -u "$TARGET_USER" -H bash -s` heredoc for nvm, Node, npm globals, and vendor tools. Preserve `-H`, the single shell (nvm is a function), and positional-argument handoff. Pass vendor JSON intact so installer argument boundaries survive.
- **State/idempotence:** OS package state, nvm files, npm listings, and executable checks determine what is installed; there is no application state store. Ubuntu skips existing packages/tools, not upgrades, but still runs `apt-get update`. Node's `--lts` selection is left to nvm.

## Key Directories

- `ubuntu/`: apt and user-toolchain provisioning. `ubuntu/nremote_decrypt/` contains a standalone mRemoteNG password-decryption CLI, not an installer component.
- `windows/`: winget and IIS provisioning. `windows/fnm/` contains shell initialization notes; `windows/ms-sql/` contains a Docker SQL Server example; `windows/other/` contains manual tool-install commands.

## Development Commands

There is no repository build, test runner, lint script, or formatter configuration. Run these commands from the repository root **only when provisioning is intended**:

| Platform | Command | Effect |
| --- | --- | --- |
| Ubuntu | `./ubuntu/ubuntu_installs.sh` | apt packages and invoking-user toolchain; do not prefix with sudo |
| Windows | `.\windows\win_installs.ps1` | machine/user winget packages |
| Windows | `.\windows\enable_iis.ps1` | IIS features and URL Rewrite; reboot may be needed |

Windows entry points require an interactive session for UAC. Before adding manifest entries, verify identifiers with `apt-cache policy <name>`, `winget search <name>`, or `npm view <name> version`. For DISM names, use `Get-WindowsOptionalFeature -Online | Where-Object FeatureName -like 'IIS-*'`.

## Code Conventions & Common Patterns

- Match surrounding indentation and naming. Bash uses strict `set -euo pipefail`, quoted arguments, uppercase configuration constants, snake_case helpers such as `apt_installed`, and colored output helpers. PowerShell uses script-local readers such as `Read-PackageList`/`Read-FeatureList`, `Join-Path`, literal-path access, and colored `Write-Host` output.
- Flat manifests are JSON string arrays. `apt_repos.json` and `vendor_scripts.json` are object arrays. Preserve the existing schemas rather than introducing another configuration layer.
- Repository entries use `name`, `key_url`, and `source_line`; vendor entries use `name`, `url`, `shell`, `check_command`, home-relative `check_path`, and `args`. Preserve HTTPS-only vendor URLs and the `bash`/`sh` whitelist. Retain both executable checks: non-interactive PATH often omits user tool directories.
- Missing/malformed manifests stop provisioning. Ubuntu aggregates apt-package/user-phase failures and exits nonzero; strict-mode failures can terminate earlier. Windows package loops do not aggregate failures; IIS logs per-feature exceptions. Do not assume uniform error semantics.
- Keep npm globals user-owned. Do not add apt `nodejs`/`npm` alongside nvm. Prefer Ubuntu packages, then justified vendor apt repositories; remote installer scripts are the last resort.
- Execution is synchronous shell/CLI orchestration, not async application code or a dependency-injection framework. Preserve privilege and shell-lifetime boundaries when refactoring.

## Important Files

- `ubuntu/ubuntu_installs.sh`: privilege handoff, install loops, and constants; currently `NVM_VERSION='v0.40.6'` and `NODE_VERSION='--lts'`.
- `ubuntu/apt_packages.json`, `apt_repos.json`, `npm_packages.json`, `vendor_scripts.json`: Ubuntu selections. Repository and npm lists are currently empty; vendor tools are uv and bun. Do not infer installed npm tools from README examples.
- `windows/machine_apps.json`, `user_apps.json`, `iis_features.json`: winget IDs/scopes and DISM features. The same winget ID may legitimately appear in both scopes; Store IDs belong in the user list.
- `README.md`: user-facing usage and provisioning guidance; update it when behavior changes.
- `.gitattributes`: forces LF for `*.sh`; CRLF breaks Linux shebangs. `.gitignore` only excludes tool metadata directories, not secrets.

## Runtime/Tooling Preferences

Use each OS's native tooling: PowerShell/winget/DISM on Windows; Bash/sudo/apt/dpkg on Ubuntu. Ubuntu requires default repositories with universe enabled and bootstraps jq/curl. Node/npm come from nvm; Bun and uv are provisioned tools, not required repository build runtimes. nvm's Node is normally available through interactive shell initialization, not automatically to root, cron, or systemd.

The decryptor requires Python 3 and the `Cryptodome` namespace (provided by `pycryptodomex`); no dependency manifest or pinned version is supplied. The SQL example requires Docker. Do not execute it unchanged: it contains an exposed sample SA password and fixed port/path/container settings. Substitute a fresh secret. The fnm notes also contain a user-specific path; adapt it and preserve existing CMD AutoRun settings.

## Testing & QA

No automated tests, CI workflows, fixtures, or coverage target are defined. Recommended non-mutating checks:

```bash
bash -n ubuntu/ubuntu_installs.sh
jq -e 'type == "array"' ubuntu/*.json windows/*.json
```

Check each jq result is `true`; this checks parsing/top-level arrays, not entry schemas. Parse changed PowerShell/Python code without executing it. For behavioral installer changes, verify on a disposable target OS, including reruns, failure handling, and correct user ownership; syntax checks do not prove provisioning behavior.

Never use provisioning, Docker startup, or remote installer commands as routine validation. Use synthetic inputs for decryptor checks: connection files and decrypted stdout contain credentials. Do not commit secrets, local connection files, or credential-bearing logs.
