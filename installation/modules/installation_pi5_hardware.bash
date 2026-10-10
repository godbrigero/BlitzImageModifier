#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BLITZ_HARDWARE_ROOT:-}"
SUDO=()
if [ "${EUID:-$(id -u)}" -ne 0 ]; then SUDO=(sudo); fi

"${SUDO[@]}" apt-get install -y --no-install-recommends \
    python3-venv gpiod libgpiod-dev python3-libgpiod python3-gpiozero python3-lgpio \
    i2c-tools python3-smbus python3-spidev \
    rpicam-apps-lite python3-libcamera python3-picamera2

for group in gpio i2c spi video render; do
    if ! getent group "$group" >/dev/null; then
        "${SUDO[@]}" groupadd --system "$group"
    fi
    "${SUDO[@]}" usermod -aG "$group" "${BLITZ_USER:-ubuntu}"
done

"${SUDO[@]}" python3 "$SCRIPT_DIR/../util/configure_pi5_boot.py" "$ROOT/boot/firmware/config.txt"
"${SUDO[@]}" mkdir -p "$ROOT/etc/udev/rules.d" "$ROOT/etc/modules-load.d"
"${SUDO[@]}" install -m 0644 "$SCRIPT_DIR/../system-patch/99-blitz-pi5-hardware.rules" "$ROOT/etc/udev/rules.d/99-blitz-pi5-hardware.rules"
printf 'i2c-dev\n' | "${SUDO[@]}" tee "$ROOT/etc/modules-load.d/blitz-pi5.conf" >/dev/null

# Nodes will be created and permissioned on first boot, not in this chroot.
echo "Pi 5 GPIO/I2C/SPI permissions and CSI camera auto-detection configured"
