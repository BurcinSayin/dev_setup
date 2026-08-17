#!/usr/bin/env bash
# Bootstrap an Ubuntu 24.04 LTS (or newer) development machine.
# Run it directly -- it re-executes itself under sudo, mirroring the way the
# Windows scripts self-elevate via Start-Process -Verb RunAs.

set -euo pipefail

# Ensure running as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf '%b\n' '\033[33mThis script requires root privileges. Relaunching with sudo...\033[0m'
    exec sudo -- "$0" "$@"
fi

# Analogue of $PSScriptRoot: manifests are always siblings of this script.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGE_LIST="$SCRIPT_DIR/apt_packages.json"
REPO_LIST="$SCRIPT_DIR/apt_repos.json"
NPM_LIST="$SCRIPT_DIR/npm_packages.json"

# Single-purpose identifiers live in the script rather than a manifest, mirroring
# $urlRewriteId in enable_iis.ps1. nvm is pinned to a tag rather than master so
# the fetched installer is deterministic; v0.40.5+ also carries the fix for
# CVE-2026-10796.
NVM_VERSION='v0.40.6'

# '--lts' tracks whatever the current Node LTS is -- Node 24 "Krypton" today,
# Node 26 automatically once it promotes in Oct 2026. Set a major like '22' to
# pin instead.
NODE_VERSION='--lts'

GREEN=$'\033[32m'
CYAN=$'\033[36m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

info() { printf '%b%s%b\n' "$CYAN" "$1" "$RESET"; }
ok()   { printf '%b%s%b\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$1" "$RESET"; }
fail() { printf '%b%s%b\n' "$RED" "$1" "$RESET"; }

# Presence check first, so a missing manifest fails before any apt work happens.
require_file() {
    local path="$1" label="$2"
    if [ ! -f "$path" ]; then
        fail "$label not found: $path"
        exit 1
    fi
}

# JSON validation needs jq, so it runs after the bootstrap step below.
require_json_array() {
    local path="$1"
    if ! jq -e 'type == "array"' "$path" >/dev/null 2>&1; then
        fail "Failed to parse JSON in ${path}: expected a JSON array"
        exit 1
    fi
}

# Emit the entries of a flat JSON string array, skipping blank/whitespace-only
# items -- the bash analogue of Read-PackageList's Where-Object filter. A POSIX
# class is used rather than \s so no backslash has to survive the shell/jq layers.
read_list() {
    jq -r '.[] | strings | select(test("^[[:space:]]*$") | not)' "$1"
}

require_file "$PACKAGE_LIST" "Package list"
require_file "$REPO_LIST" "Repository list"
require_file "$NPM_LIST" "npm package list"

export DEBIAN_FRONTEND=noninteractive

ok "Refreshing package index..."
apt-get update

# jq parses the manifests and curl fetches repository signing keys, so both must
# exist before the manifest-driven loops run. Both are also listed in
# apt_packages.json; apt is idempotent, so the install loop simply reports them
# as already present.
info "Bootstrapping jq and curl (manifest parser and key fetcher)..."
apt-get install -y --no-install-recommends jq curl

require_json_array "$PACKAGE_LIST"
require_json_array "$REPO_LIST"
require_json_array "$NPM_LIST"

# --- Third-party apt repositories -------------------------------------------
# apt_repos.json ships empty. Each entry is an object:
#   { "name": "...", "key_url": "https://...", "source_line": "deb [signed-by=...] ..." }
# This is the one documented exception to the flat-array manifest rule.

repos_added=0
while IFS=$'\t' read -r name key_url source_line; do
    [ -n "$name" ] || continue

    keyring="/etc/apt/keyrings/${name}.asc"
    listfile="/etc/apt/sources.list.d/${name}.list"

    if [ -f "$keyring" ] && [ -f "$listfile" ]; then
        info "Repository $name already registered; skipping."
        continue
    fi

    info "Registering repository $name..."
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL "$key_url" -o "$keyring"; then
        fail "  Failed to fetch signing key for $name from $key_url"
        rm -f "$keyring"
        continue
    fi
    chmod a+r "$keyring"
    printf '%s\n' "$source_line" >"$listfile"
    repos_added=$((repos_added + 1))
done < <(jq -r '.[] | select(type == "object") | [.name // "", .key_url // "", .source_line // ""] | @tsv' "$REPO_LIST")

if [ "$repos_added" -gt 0 ]; then
    ok "Registered $repos_added repository/repositories. Refreshing index..."
    apt-get update
fi

# --- Packages ----------------------------------------------------------------
# Per-package installs, so one bad name fails loudly without aborting the rest --
# matching the non-aborting behaviour of the winget loop in win_installs.ps1.

mapfile -t packages < <(read_list "$PACKAGE_LIST")

installed=0
failed_pkgs=()

if [ "${#packages[@]}" -eq 0 ]; then
    warn "No packages listed in $PACKAGE_LIST; skipping the apt phase."
else
    ok "Starting installations..."
    for pkg in "${packages[@]}"; do
        info "Installing $pkg..."
        if apt-get install -y "$pkg"; then
            installed=$((installed + 1))
        else
            fail "  Failed to install $pkg"
            failed_pkgs+=("$pkg")
        fi
    done
fi

# --- User phase: nvm, Node LTS, global npm packages --------------------------
# nvm lives in $HOME/.nvm as a shell function, and the Claude Code docs warn
# explicitly against `sudo npm install -g`, so this phase drops back down to the
# invoking user. It has to be a single heredoc: nvm is a function rather than a
# binary, so it exists only inside the shell that sourced it.

TARGET_USER="${DEV_SETUP_USER:-${SUDO_USER:-}}"
user_phase_skipped=""
user_phase_failed=0

if [ -z "$TARGET_USER" ]; then
    user_phase_skipped="SUDO_USER is unset, so this ran as real root"
elif [ "$TARGET_USER" = "root" ] && [ -z "${DEV_SETUP_USER:-}" ]; then
    user_phase_skipped="the invoking user resolved to root"
elif ! id "$TARGET_USER" >/dev/null 2>&1; then
    user_phase_skipped="user '$TARGET_USER' does not exist"
fi

echo
if [ -n "$user_phase_skipped" ]; then
    warn "=========================================================================="
    warn " Skipping nvm / Node / npm: $user_phase_skipped."
    warn " Installing them under /root would leave them unusable from your account."
    warn " Re-run this script as your normal user, or set DEV_SETUP_USER=<name>."
    warn "=========================================================================="
else
    mapfile -t npm_packages < <(read_list "$NPM_LIST")
    npm_list_text=""
    if [ "${#npm_packages[@]}" -gt 0 ]; then
        npm_list_text="$(printf '%s\n' "${npm_packages[@]}")"
    fi

    ok "Setting up nvm, Node ($NODE_VERSION) and npm globals for user '$TARGET_USER'..."

    # -H is mandatory: without it HOME stays /root and nvm installs to the wrong
    # place. Values cross as positional args rather than environment variables so
    # that a strict sudoers env policy cannot strip them.
    if sudo -u "$TARGET_USER" -H bash -s -- \
            "$NVM_VERSION" "$NODE_VERSION" "$npm_list_text" <<'USERPHASE'
set -euo pipefail
nvm_version="$1"
node_version="$2"
npm_packages="$3"

export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "nvm already present at $NVM_DIR; skipping bootstrap."
else
    echo "Installing nvm $nvm_version into $NVM_DIR..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
fi

# nvm is a shell function, so it must be sourced here to be callable at all.
. "$NVM_DIR/nvm.sh"

echo "Installing Node ${node_version}..."
nvm install "$node_version"
nvm alias default 'lts/*'
nvm use --lts

echo "Active: node $(node --version), npm $(npm --version)"

status=0
while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    echo "Installing npm package $pkg..."
    if ! npm install -g "$pkg"; then
        echo "  Failed to install npm package $pkg" >&2
        status=1
    fi
done <<<"$npm_packages"
exit "$status"
USERPHASE
    then
        ok "nvm, Node and npm globals are set up for '$TARGET_USER'."
    else
        fail "  The nvm / Node / npm phase reported a failure."
        user_phase_failed=1
    fi
fi

# --- Summary -----------------------------------------------------------------

echo
if [ "${#failed_pkgs[@]}" -gt 0 ] || [ "$user_phase_failed" -ne 0 ]; then
    fail "=========================================================================="
    fail " apt packages installed: $installed of ${#packages[@]}"
    if [ "${#failed_pkgs[@]}" -gt 0 ]; then
        fail " apt failures: ${failed_pkgs[*]}"
        fail " Verify names with 'apt-cache policy <name>' before editing the manifest."
    fi
    if [ "$user_phase_failed" -ne 0 ]; then
        fail " nvm / Node / npm phase failed -- see the output above."
    fi
    fail "=========================================================================="
    exit 1
fi

ok "Done. Installed $installed of ${#packages[@]} apt packages with no failures."
if [ -z "$user_phase_skipped" ]; then
    ok "Open a new shell (or run 'source ~/.bashrc') to pick up nvm, node and claude."
fi
