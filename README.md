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
└── ubuntu/           Ubuntu 24.04 LTS+ — bash + apt + nvm + vendor scripts
    ├── ubuntu_installs.sh
    ├── apt_packages.json
    ├── npm_packages.json
    ├── vendor_scripts.json
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

It runs in two phases. **System packages** install as root via apt:

| Package | Binary | Notes |
|---|---|---|
| `git` | `git` | |
| `gh` | `gh` | GitHub CLI — from `universe`, enabled by default on 24.04 |
| `curl` | `curl` | also bootstraps nvm and fetches repo signing keys |
| `wget` | `wget` | |
| `jq` | `jq` | also parses these manifests |
| `7zip` | `7zz` | on 22.04 and earlier this package is `p7zip-full` |
| `ca-certificates` | — | TLS trust for the nvm, npm and uv downloads |
| `ripgrep` | `rg` | optional; Claude Code bundles its own, this is a fallback |
| `ruby-full` | `ruby` | Ruby plus stdlib/headers; from `universe` |
| `unzip` | `unzip` | required by bun's installer, which aborts without it |

Then the **user toolchain** installs as *you*, never as root:

| Tool | Source | Notes |
|---|---|---|
| nvm | `v0.40.6` install script | into `~/.nvm` |
| node + npm | `nvm install --lts` | current LTS, resolved at install time — not a pinned major |
| `claude` | `npm install -g` from `npm_packages.json` | Claude Code |
| `uv` | `vendor_scripts.json` | Python package manager, into `~/.local/bin` |
| `bun` | `vendor_scripts.json` | JavaScript runtime + package manager, into `~/.bun/bin` |

After it finishes, open a new shell (or `source ~/.bashrc`) so nvm and the vendor tools are on your `PATH`:

```bash
node --version       # current LTS
claude --version
uv --version
bun --version
```

Individual failures in either phase are reported but do not abort the run; the script prints a red summary and exits non-zero if anything failed.

### Re-running

Every step checks before it acts, so a second run on the same machine does no package-manager work — it just reports what is already there:

```
git is already installed; skipping.
gh is already installed; skipping.
...
npm package @anthropic-ai/claude-code is already installed; skipping.
uv is already installed; skipping.
bun is already installed; skipping.

Done. 0 apt package(s) installed, 10 already present, 0 failures (of 10).
```

This is a *skip*, not an upgrade — re-running will not pull newer versions of things you already have. Patch those the normal way:

```bash
sudo apt-get update && sudo apt-get upgrade   # system packages
npm update -g                                 # global CLI tools
uv self update && bun upgrade                 # vendor tools
```

Node is the exception: `nvm install --lts` is left to nvm's own check, so the script still follows the LTS line onto a new major when one promotes.

The vendor tools resolve the latest release at install time too, but only on the *first* install — once the binary exists the script skips it entirely and never upgrades it in passing.

### If you run it as root

nvm, npm globals and uv are per-user by design, so the script refuses to install them into `/root` by accident. If `SUDO_USER` is unset — you launched from a real root shell — it warns and skips that phase rather than putting an unusable toolchain in root's home.

Run it as your normal user, or name the account explicitly:

```bash
DEV_SETUP_USER=alice ./ubuntu/ubuntu_installs.sh
```

### Where nvm's node is visible

nvm is sourced from `~/.bashrc`, so `node` and `npm` exist in **interactive shells only**. `cron`, `systemd` units, and root will not find them. If a service ever needs Node, install it system-wide via an `apt_repos.json` entry (NodeSource) — nvm is not the right tool for that.

### Adding a vendor install script

Some tools ship no apt package and no apt repo — `uv` and `bun` are the current examples. Those live in `vendor_scripts.json`, so adding or removing one is a JSON edit rather than a script change:

```json
{
  "name": "bun",
  "url": "https://bun.com/install",
  "shell": "bash",
  "check_command": "bun",
  "check_path": ".bun/bin/bun",
  "args": []
}
```

`check_path` is relative to your home directory, and is what makes re-runs cheap — the install phase is non-interactive, so a newly created `~/.bun/bin` usually isn't on `PATH` yet and `check_command` alone would reinstall every time. Pin a version the way the vendor supports it: uv takes one in the URL (`https://astral.sh/uv/0.12.5/install.sh`), bun as an argument (`"args": ["bun-v1.2.0"]`). The loop refuses non-https URLs and any `shell` other than `bash` or `sh`.

Check the installer before adding an entry — bun's aborts outright without `unzip`, which is why `unzip` is in `apt_packages.json`.

This is the last-resort lane: prefer an apt package, then an apt repo below.

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

**Ubuntu is not a mirror of Windows.** It gets a deliberately minimal CLI core plus a Node toolchain. GUI apps (Postman, JetBrains Toolbox, Dropbox, pCloud, Antigravity IDE) and Windows-only apps (Notepad++, SumatraPDF, mRemoteNG, Bitvise SSH Client) are out of scope, as is AWS CLI v2 (no official apt repo).

**The two machines manage Node differently.** Windows uses Volta; Ubuntu uses nvm. A deliberate divergence, but worth knowing before you expect `volta` on the Linux box.

**There is no Ubuntu equivalent of `enable_iis.ps1`, by design.** It provisions IIS for ASP.NET 4.8, which is .NET Framework and does not run on Linux at all. Linux hosting for modern .NET is deferred rather than cancelled — when wanted, it attaches as a new `ubuntu/` script using `apt_repos.json` to register the Microsoft package repo, with no restructuring needed.

## Adding packages

Verify the identifier before adding it — a wrong name fails without aborting the run on either OS.

```powershell
winget search <name>          # Windows  -> machine_apps.json / user_apps.json
```
```bash
apt-cache policy <name>       # Ubuntu   -> apt_packages.json
npm view <name> version       # Ubuntu   -> npm_packages.json
```

Put system packages in `apt_packages.json` and user-scoped CLI tools in `npm_packages.json`. Note that `nodejs` and `npm` are intentionally **not** apt packages here — installing them would put a second Node on `PATH` fighting with nvm's.

Tools with no apt package and no apt repo go in `vendor_scripts.json` instead — see "Adding a vendor install script" above, and "Install sources" in `CLAUDE.md` for when that lane is the right one.
