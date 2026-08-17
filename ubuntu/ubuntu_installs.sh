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
VENDOR_LIST="$SCRIPT_DIR/vendor_scripts.json"

# Single-purpose identifiers live in the script rather than a manifest, mirroring
# $urlRewriteId in enable_iis.ps1. nvm is pinned to a tag rather than master so
# the fetched installer is deterministic; v0.40.5+ also carries the fix for
# CVE-2026-10796.
NVM_VERSION='v0.40.6'

# '--lts' tracks whatever the current Node LTS is -- Node 24 "Krypton" today,
# Node 26 automatically once it promotes in Oct 2026. Set a major like '22' to
# pin instead.
NODE_VERSION='--lts'

# Everything else that installs from a vendor script -- uv, bun -- lives in
# vendor_scripts.json rather than in constants here, so tools can be added or
# dropped by editing JSON. nvm stays hardcoded above because it is not that
# shape: it is a shell function the rest of the user phase has to source and
# then call, not a self-contained binary that can be installed and forgotten.

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

# dpkg's own view of a package. ${db:Status-Status} collapses the usual
# "install ok installed" triplet down to just "installed"; every other state
# (not-installed, config-files left behind by a removal, an unrecognised name)
# falls through to the install path, which is the safe direction. dpkg-query is
# always present, so this works before the jq/curl bootstrap below.
apt_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

require_file "$PACKAGE_LIST" "Package list"
require_file "$REPO_LIST" "Repository list"
require_file "$NPM_LIST" "npm package list"
require_file "$VENDOR_LIST" "Vendor script list"

export DEBIAN_FRONTEND=noninteractive

ok "Refreshing package index..."
apt-get update

# jq parses the manifests and curl fetches repository signing keys, so both must
# exist before the manifest-driven loops run. Both are also listed in
# apt_packages.json; that is not a duplicate, because the install loop below
# skips whatever is already installed -- including anything this step just added.
bootstrap_missing=()
for pkg in jq curl; do
    apt_installed "$pkg" || bootstrap_missing+=("$pkg")
done

if [ "${#bootstrap_missing[@]}" -gt 0 ]; then
    info "Bootstrapping ${bootstrap_missing[*]} (manifest parser and key fetcher)..."
    apt-get install -y --no-install-recommends "${bootstrap_missing[@]}"
else
    info "jq and curl are already installed; skipping bootstrap."
fi

require_json_array "$PACKAGE_LIST"
require_json_array "$REPO_LIST"
require_json_array "$NPM_LIST"
require_json_array "$VENDOR_LIST"

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
#
# Anything dpkg already reports as installed is logged and skipped outright. That
# makes a re-run fast and honest, at the cost of no longer upgrading in passing:
# 'apt-get install' on an outdated package used to pull the newer version. Use
# 'apt-get upgrade' for that -- this script provisions, it does not patch.

mapfile -t packages < <(read_list "$PACKAGE_LIST")

installed=0
already=0
failed_pkgs=()

if [ "${#packages[@]}" -eq 0 ]; then
    warn "No packages listed in $PACKAGE_LIST; skipping the apt phase."
else
    ok "Starting installations..."
    for pkg in "${packages[@]}"; do
        if apt_installed "$pkg"; then
            info "$pkg is already installed; skipping."
            already=$((already + 1))
            continue
        fi

        info "Installing $pkg..."
        if apt-get install -y "$pkg"; then
            installed=$((installed + 1))
        else
            fail "  Failed to install $pkg"
            failed_pkgs+=("$pkg")
        fi
    done
fi

# --- User phase: nvm, Node LTS, npm globals, vendor scripts ------------------
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

    ok "Setting up nvm, Node ($NODE_VERSION), npm globals and vendor tools for user '$TARGET_USER'..."

    # -H is mandatory: without it HOME stays /root and nvm installs to the wrong
    # place. Values cross as positional args rather than environment variables so
    # that a strict sudoers env policy cannot strip them. The vendor manifest
    # crosses as its raw JSON text and is parsed with jq on the far side, which
    # keeps per-entry fields (notably 'args') intact -- a flattened TSV would
    # lose the boundary between arguments.
    if sudo -u "$TARGET_USER" -H bash -s -- \
            "$NVM_VERSION" "$NODE_VERSION" "$npm_list_text" "$(cat "$VENDOR_LIST")" <<'USERPHASE'
set -euo pipefail
nvm_version="$1"
node_version="$2"
npm_packages="$3"
vendor_json="$4"

export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "nvm already present at $NVM_DIR; skipping bootstrap."
else
    echo "Installing nvm $nvm_version into $NVM_DIR..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
fi

# nvm is a shell function, so it must be sourced here to be callable at all.
#
# nvm's own code is not 'set -u' clean, so nounset has to come off around these
# calls. Specifically, 'nvm use --lts' sets NVM_LTS and takes a branch that never
# assigns PROVIDED_VERSION, then dereferences it bare at nvm.sh:4199 --
# 'if [ -n "${PROVIDED_VERSION}" ]', with no '-' fallback, unlike the
# '${NVM_USE_OUTPUT-}' guard ten lines below it. Under nounset that aborts the
# whole phase with "PROVIDED_VERSION: unbound variable" even though Node is fine.
# 'nvm install' escapes it only because it assigns PROVIDED_VERSION itself.
# Restore -u afterwards so our own logic keeps the protection.
set +u
. "$NVM_DIR/nvm.sh"

echo "Installing Node ${node_version}..."
nvm install "$node_version"
nvm alias default 'lts/*'
nvm use --lts
set -u

echo "Active: node $(node --version), npm $(npm --version)"

# 'npm ls -g --depth=0 <name>' exits 0 only when the package sits in the global
# root, and handles scoped names such as @anthropic-ai/claude-code. Its failure
# mode is benign: any non-zero exit falls through to 'npm install -g', which is
# exactly what this loop did unconditionally before.
status=0
while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
        echo "npm package $pkg is already installed; skipping."
        continue
    fi
    echo "Installing npm package $pkg..."
    if ! npm install -g "$pkg"; then
        echo "  Failed to install npm package $pkg" >&2
        status=1
    fi
done <<<"$npm_packages"

# --- Vendor install scripts --------------------------------------------------
# Driven by vendor_scripts.json. Each entry is a standalone installer that drops
# a self-contained binary somewhere under $HOME, so none of this needs root and
# none of it needs Node. Fields:
#
#   name           label used in the log lines (required)
#   url            https installer URL, piped to the shell below (required)
#   shell          'bash' or 'sh' -- whichever the vendor documents
#   check_command  binary name to look for on PATH
#   check_path     path to the binary, relative to $HOME
#   args           positional arguments for the installer, e.g. a version tag
#
# Both checks are needed. This is a non-interactive shell, so a freshly added
# ~/.local/bin or ~/.bun/bin may not be on PATH yet and 'command -v' alone would
# reinstall on every run; check_path covers that. It is relative to $HOME so the
# manifest never has to carry a shell variable that would need expanding here.
#
# Pinning is per-vendor and lives in the manifest: uv takes a version in its URL
# (https://astral.sh/uv/0.12.5/install.sh), bun takes one as an argument
# (["bun-v1.2.0"]). Left as shipped, both resolve the current release at install
# time. As everywhere else this is a skip, not an upgrade -- an already-present
# tool is left alone, and updating it is its own deliberate act.

vendor_count=$(jq 'length' <<<"$vendor_json")
vendor_index=0
while [ "$vendor_index" -lt "$vendor_count" ]; do
    entry=$(jq -c ".[$vendor_index]" <<<"$vendor_json")
    vendor_index=$((vendor_index + 1))

    v_name=$(jq -r '.name // ""' <<<"$entry")
    v_url=$(jq -r '.url // ""' <<<"$entry")
    v_shell=$(jq -r '.shell // "bash"' <<<"$entry")
    v_command=$(jq -r '.check_command // ""' <<<"$entry")
    v_path=$(jq -r '.check_path // ""' <<<"$entry")
    mapfile -t v_args < <(jq -r '.args // [] | .[] | strings' <<<"$entry")

    if [ -z "$v_name" ] || [ -z "$v_url" ]; then
        echo "  Skipping malformed vendor entry: 'name' and 'url' are both required" >&2
        status=1
        continue
    fi

    # These two guards are the point of validating a manifest whose whole purpose
    # is to execute remote code: plain http would make the payload trivially
    # tamperable, and the interpreter is not a free-text field.
    case "$v_url" in
        https://*) ;;
        *)  echo "  Refusing to run the $v_name installer: url is not https ($v_url)" >&2
            status=1
            continue ;;
    esac
    case "$v_shell" in
        bash|sh) ;;
        *)  echo "  Refusing to run the $v_name installer: shell must be bash or sh, got '$v_shell'" >&2
            status=1
            continue ;;
    esac

    if { [ -n "$v_command" ] && command -v "$v_command" >/dev/null 2>&1; } ||
       { [ -n "$v_path" ] && [ -x "$HOME/$v_path" ]; }; then
        echo "$v_name is already installed; skipping."
        continue
    fi

    echo "Installing $v_name from $v_url..."
    if ! curl -fsSL "$v_url" | "$v_shell" -s -- ${v_args[@]+"${v_args[@]}"}; then
        echo "  Failed to install $v_name" >&2
        status=1
    fi
done

exit "$status"
USERPHASE
    then
        ok "nvm, Node, npm globals and vendor tools are set up for '$TARGET_USER'."
    else
        fail "  The nvm / Node / npm / vendor phase reported a failure."
        user_phase_failed=1
    fi
fi

# --- Summary -----------------------------------------------------------------

echo
if [ "${#failed_pkgs[@]}" -gt 0 ] || [ "$user_phase_failed" -ne 0 ]; then
    fail "=========================================================================="
    fail " apt packages: $installed installed, $already already present, ${#failed_pkgs[@]} failed (of ${#packages[@]})"
    if [ "${#failed_pkgs[@]}" -gt 0 ]; then
        fail " apt failures: ${failed_pkgs[*]}"
        fail " Verify names with 'apt-cache policy <name>' before editing the manifest."
    fi
    if [ "$user_phase_failed" -ne 0 ]; then
        fail " nvm / Node / npm / vendor phase failed -- see the output above."
    fi
    fail "=========================================================================="
    exit 1
fi

ok "Done. $installed apt package(s) installed, $already already present, 0 failures (of ${#packages[@]})."
if [ -z "$user_phase_skipped" ]; then
    ok "Open a new shell (or run 'source ~/.bashrc') to pick up nvm, node, claude and the vendor tools."
fi
