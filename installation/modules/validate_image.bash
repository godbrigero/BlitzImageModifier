#!/bin/bash
set -euo pipefail

ROOT="${BLITZ_INSTALLATION_DIR:-/opt/blitz}/B.L.I.T.Z"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
BLITZ_PATH="$ROOT" .venv/bin/python "$SCRIPT_DIR/../util/check_blitz_runtime.py"
BLITZ_PATH="$ROOT" .venv/bin/python -c 'import watchdog.__main__; print("Watchdog startup imports verified")'

for service in blitz-startup autobahn ssh avahi-daemon; do
    systemctl is-enabled "$service" >/dev/null
    echo "First-boot service enabled: $service"
    if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
        sudo systemctl is-active "$service" >/dev/null || {
            sudo systemctl status "$service" --no-pager >&2 || true
            sudo journalctl -u "$service" -n 40 --no-pager >&2 || true
            exit 1
        }
    fi
done

if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
    if ! BLITZ_PATH="$ROOT" .venv/bin/python "$SCRIPT_DIR/../util/check_watchdog_http.py"; then
        sudo journalctl -u blitz-startup -n 40 --no-pager >&2 || true
        exit 1
    fi
fi

test -x /usr/local/bin/autobahn
test -r /etc/autobahn/config.toml
grep -qxF "User=${BLITZ_USER:-ubuntu}" /etc/systemd/system/blitz-startup.service
test "$(stat -c '%U' "$ROOT")" = "${BLITZ_USER:-ubuntu}"
test -x /usr/local/bin/blitzprojstartup.bash
if [ "${BLITZ_DEVICE:-}" = pi5 ] || [ "${BLITZ_DEVICE:-}" = jetson ]; then
    test -r /etc/udev/rules.d/90-usb-port-names.rules
fi
sudo -u "${BLITZ_USER:-ubuntu}" env BLITZ_PATH="$ROOT" .venv/bin/python "$SCRIPT_DIR/../util/smoke_blitz_module.py"
if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    sudo -u "${BLITZ_USER:-ubuntu}" .venv/bin/python -c 'import os, tempfile; temporary = tempfile.TemporaryDirectory(prefix="blitz-hardware-import-"); os.chdir(temporary.name); import picamera2, libcamera, gpiozero, lgpio, gpiod, smbus, spidev; print("Pi camera and GPIO Python bindings verified in BLITZ venv")'
    sudo -u "${BLITZ_USER:-ubuntu}" .venv/bin/python -c 'import numpy as np, simplejpeg; a = np.zeros((8, 8, 3), dtype=np.uint8); assert simplejpeg.decode_jpeg(simplejpeg.encode_jpeg(a)).shape == a.shape; print("Camera JPEG/NumPy ABI verified")'
    for group in gpio i2c spi video render; do
        id -nG "${BLITZ_USER:-ubuntu}" | tr ' ' '\n' | grep -qxF "$group"
    done
    for setting in camera_auto_detect=1 dtparam=i2c_arm=on dtparam=spi=on; do
        grep -qxF "$setting" /boot/firmware/config.txt
    done
    command -v rpicam-hello >/dev/null
    test -r /etc/udev/rules.d/99-blitz-pi5-hardware.rules
    echo "Pi 5 hardware settings and permissions verified (device detection requires boot)"
fi
echo "Image runtime, services, ownership, and module launch verified"
