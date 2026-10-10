#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
trap 'status=$?; echo "BLITZ installation failed at line $LINENO (exit $status). See the preceding command output." >&2; exit "$status"' ERR
export BLITZ_INSTALLATION_DIR="${BLITZ_INSTALLATION_DIR:-/opt/blitz}"

# Provision the target image account before installing application files.
if [ "${BLITZ_IMAGE_BUILD:-false}" = true ]; then
    bash ./provision_user.bash
else
    export BLITZ_USER="${BLITZ_USER:-$(id -un)}"
    if [ "$BLITZ_USER" = root ] || ! id "$BLITZ_USER" >/dev/null 2>&1; then
        echo "Live installation requires an existing non-root BLITZ_USER." >&2
        exit 1
    fi
    sudo mkdir -p "$BLITZ_INSTALLATION_DIR"
    sudo chown "$BLITZ_USER:$(id -gn "$BLITZ_USER")" "$BLITZ_INSTALLATION_DIR"
fi

# Install system dependencies
bash ./installation_common.bash

if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    bash ./installation_pi5_hardware.bash
fi

# Install BLITZ software
bash ./installation_blitz.bash
if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    bash ./installation_pi5_python.bash
fi

# Install Autobahn
bash ./installation_autobahn.bash

# Install startup script
bash ./install_startup.bash
bash ./install_device_rules.bash

# Make the normal device user own the deployable application tree.
if [ "$(id -u)" = 0 ]; then
    bash ./finalize_permissions.bash
else
    sudo env BLITZ_USER="$BLITZ_USER" BLITZ_INSTALLATION_DIR="$BLITZ_INSTALLATION_DIR" \
        bash ./finalize_permissions.bash
fi

# Restart after ownership and optional hardware Python packages are finalized.
if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
    sudo systemctl restart autobahn blitz-startup
fi

# Check everything needed at first boot, not only the deployment API imports.
bash ./validate_image.bash
