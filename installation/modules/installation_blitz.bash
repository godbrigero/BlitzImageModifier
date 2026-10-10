#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="${BLITZ_INSTALLATION_DIR:-/opt/blitz}"
DEFAULT_PI_NAME="${BLITZ_DEFAULT_PI_NAME:-blitz-pi-random-name-1234}"
BLITZ_GIT_URL="${BLITZ_GIT_URL:-https://github.com/PinewoodRobotics/B.L.I.T.Z.git}"
BLITZ_REF="${BLITZ_REF:-HEAD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$INSTALLATION_DIR/B.L.I.T.Z"

mkdir -p "$INSTALLATION_DIR"
if [ -e "$SOURCE_DIR" ]; then
    echo "BLITZ destination already exists: $SOURCE_DIR. Use a fresh image/install directory." >&2
    exit 1
fi

# The installer, setup script, and runtime must come from the same checkout.
if [ -n "${BLITZ_SOURCE_DIR:-}" ]; then
    if [ ! -f "$BLITZ_SOURCE_DIR/scripts/ui/install_on_system.sh" ]; then
        echo "BLITZ_SOURCE_DIR must point to a complete BLITZ source tree." >&2
        exit 1
    fi
    mkdir -p "$SOURCE_DIR"
    # Copy working-tree changes while excluding development caches/artifacts.
    rsync -a --exclude='.git' --exclude='.venv' --exclude='build' \
        --exclude='__pycache__' --exclude='.pytest_cache' --exclude='node_modules' \
        --exclude='*.egg-info' --exclude='.env*' --exclude='system_data/name.txt' \
        --exclude='website' --exclude='.ssh' "$BLITZ_SOURCE_DIR/" "$SOURCE_DIR/"
else
    git clone "$BLITZ_GIT_URL" "$SOURCE_DIR"
    if git -C "$SOURCE_DIR" rev-parse --verify "${BLITZ_REF}^{commit}" >/dev/null 2>&1; then
        git -C "$SOURCE_DIR" checkout --detach "$BLITZ_REF"
    else
        git -C "$SOURCE_DIR" checkout --detach "origin/$BLITZ_REF"
    fi
fi

# Raspberry Pi's libcamera/Picamera2 bindings belong to the distro's Python.
# Expose them only on images explicitly provisioned for those interfaces.
if [ "${BLITZ_PYTHON_SYSTEM_PACKAGES:-false}" = true ]; then
    python3 -m venv --system-site-packages "$SOURCE_DIR/.venv"
fi

TARGET_NAME="$DEFAULT_PI_NAME" \
TARGET_FOLDER="$INSTALLATION_DIR" \
SERVICE_NAME="blitz-startup" \
SERVICE_USER="${BLITZ_USER:-ubuntu}" \
DEV_LOCAL_OVERRIDE=true \
BLITZ_ASSUME_YES=true \
bash "$SOURCE_DIR/scripts/ui/install_on_system.sh"

# Fail image creation immediately if target runtime and deployment APIs disagree.
cd "$SOURCE_DIR"
BLITZ_PATH="$SOURCE_DIR" .venv/bin/python "$SCRIPT_DIR/../util/check_blitz_runtime.py"
