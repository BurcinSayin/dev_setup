# dev_setup

JSON-driven bootstrappers for a fresh development machine. Pick your OS folder and run one script.

```
dev_setup/
├── windows/          Windows 11 — PowerShell + winget + DISM
│   ├── win_installs.ps1
│   ├── enable_iis.ps1
│   ├── machine_apps.json
│   ├── user_apps.json
│   └── iis_features.json
└── ubuntu/           Ubuntu 24.04 LTS+ — bash + apt
    ├── ubuntu_installs.sh
    ├── apt_packages.json
    └── apt_repos.json
```

Each script reads the JSON manifests sitting next to it. To change what gets installed, edit the JSON — not the script.

---

## Windows

**Requires:** Windows 11 with winget (App Installer) available, and an interactive PowerShell session — the scripts self-elevate via UAC.

```powershell
.\windows\win_installs.ps1     # install all winget packages
.\windows\enable_iis.ps1       # enable IIS for ASP.NET 4.8 hosting
```

`win_installs.ps1` installs from two manifests: `machine_apps.json` (`--scope machine`) and `user_apps.json` (`--scope user`, may contain Microsoft Store IDs). A package can appear in both when it ships separate per-scope installers.

`enable_iis.ps1` enables the DISM features in `iis_features.json` and installs the URL Rewrite module. **A full reboot is normally required afterwards** — `iisreset` is not enough for features reporting `RestartNeeded`. The script warns you when that happens.

winget is idempotent, so re-running is safe and skips what is already installed.

---

## Ubuntu

**Requires:** Ubuntu 24.04 LTS or newer, and a user with sudo rights.

```bash
./ubuntu/ubuntu_installs.sh    # note: no sudo prefix
```

The script re-executes itself under `sudo`, mirroring how the Windows scripts self-elevate. You will be prompted for your password once.

Installs the minimal shared CLI core:

| Package | Binary | Notes |
|---|---|---|
| `git` | `git` | |
| `gh` | `gh` | GitHub CLI — from `universe`, enabled by default on 24.04 |
| `curl` | `curl` | also used to fetch repo signing keys |
| `wget` | `wget` | |
| `jq` | `jq` | also used to parse these manifests |
| `7zip` | `7zz` | on 22.04 and earlier this package is `p7zip-full` |

Individual package failures are reported but do not abort the run; the script prints a red summary and exits non-zero if anything failed. apt is idempotent, so re-running is safe.

### Adding a third-party apt repo

`apt_repos.json` ships empty. Add an object and the script registers the repo before installing:

```json
[
  {
    "name": "docker",
    "key_url": "https://download.docker.com/linux/ubuntu/gpg",
    "source_line": "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable"
  }
]
```

Prefer a default-repo package where one exists — a vendor repo is real maintenance cost.

---

## Scope notes

**Ubuntu is not a mirror of Windows.** It gets a deliberately minimal CLI core. GUI apps (Postman, JetBrains Toolbox, Dropbox, pCloud, Antigravity IDE) and Windows-only apps (Notepad++, SumatraPDF, mRemoteNG, Bitvise SSH Client) are out of scope, as are tools with no official apt repo (Volta, AWS CLI v2).

**There is no Ubuntu equivalent of `enable_iis.ps1`, by design.** It provisions IIS for ASP.NET 4.8, which is .NET Framework and does not run on Linux at all. Linux hosting for modern .NET is deferred rather than cancelled — when wanted, it attaches as a new `ubuntu/` script using `apt_repos.json` to register the Microsoft package repo, with no restructuring needed.

## Adding packages

Verify the identifier before adding it — a wrong name fails without aborting the run on either OS.

```powershell
winget search <name>          # Windows
```
```bash
apt-cache policy <name>       # Ubuntu
```
