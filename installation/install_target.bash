#!/bin/bash
# Install into an already booted vendor/distro OS. Image compilation uses pi5.bash.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="${1:-}"
export BLITZ_USER="${BLITZ_USER:-$(id -un)}"
export BLITZ_RESUME_INSTALL=true
export BLITZ_IMAGE_BUILD=false
if [ "$BLITZ_USER" = root ]; then
    echo "Run as a normal login user, without sudo." >&2
    exit 1
fi
case "$DEVICE" in
    jetson|jetson-nano|jetson-orin-nano)
        exec bash "$SCRIPT_DIR/extra/jetson_nano.bash"
        ;;
    pi5)
        export BLITZ_DEVICE=pi5 BLITZ_PYTHON_SYSTEM_PACKAGES=true
        ;;
    linux)
        export BLITZ_DEVICE=linux BLITZ_PYTHON_SYSTEM_PACKAGES=false
        ;;
    *) echo "Usage: bash installation/install_target.bash {pi5|jetson|jetson-nano|jetson-orin-nano|linux}" >&2; exit 1 ;;
esac
bash "$SCRIPT_DIR/modules/main_startup.bash"
echo "Target installation verified. Reboot to apply hardware/device-name settings."
