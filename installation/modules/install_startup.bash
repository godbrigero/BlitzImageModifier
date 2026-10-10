#!/bin/bash
set -euo pipefail

# /workspace is shared across image builds; preserve the source script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo install -m 0755 "$SCRIPT_DIR/../system-patch/blitzprojstartup.bash" /usr/local/bin/blitzprojstartup.bash
line="sudo /usr/local/bin/blitzprojstartup.bash"
BASHRC_PATH="${BLITZ_BASHRC_PATH:-/etc/bash.bashrc}"
if ! grep -qxF "$line" "$BASHRC_PATH"; then
    printf '%s\n' "$line" | sudo tee -a "$BASHRC_PATH" >/dev/null
fi
