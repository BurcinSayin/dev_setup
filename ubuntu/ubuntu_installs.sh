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

require_file "$PACKAGE_LIST" "Package list"
require_file "$REPO_LIST" "Repository list"

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

# POSIX class rather than \s: no backslash escaping to survive shell/jq layers.
mapfile -t packages < <(jq -r '.[] | strings | select(test("^[[:space:]]*$") | not)' "$PACKAGE_LIST")

if [ "${#packages[@]}" -eq 0 ]; then
    warn "No packages listed in $PACKAGE_LIST. Nothing to do."
    exit 0
fi

ok "Starting installations..."

installed=0
failed_pkgs=()

for pkg in "${packages[@]}"; do
    info "Installing $pkg..."
    if apt-get install -y "$pkg"; then
        installed=$((installed + 1))
    else
        fail "  Failed to install $pkg"
        failed_pkgs+=("$pkg")
    fi
done

echo
if [ "${#failed_pkgs[@]}" -gt 0 ]; then
    fail "=========================================================================="
    fail " Installed: $installed of ${#packages[@]}"
    fail " Failed:    ${failed_pkgs[*]}"
    fail " Verify names with 'apt-cache policy <name>' before editing the manifest."
    fail "=========================================================================="
    exit 1
fi

ok "Done. Installed $installed of ${#packages[@]} packages with no failures."
