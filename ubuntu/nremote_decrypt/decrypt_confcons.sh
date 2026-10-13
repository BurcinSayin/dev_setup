#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Decrypted credentials are printed to stdout; do not capture them in shared logs.
exec uv run --with pycryptodomex python "$SCRIPT_DIR/mremoteng_decrypt.py" \
    --realFile '/run/media/orin/New Volume/tmp/mRemoteNG/confCons.xml' "$@"
