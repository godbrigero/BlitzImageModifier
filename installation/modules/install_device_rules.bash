#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${BLITZ_DEVICE:-}" in
    pi5) RULE=90-usb-port-names.rules ;;
    jetson) RULE=90-usb-port-names-jetson.rules ;;
    *) exit 0 ;;
esac
sudo install -m 0644 "$SCRIPT_DIR/../system-patch/$RULE" /etc/udev/rules.d/90-usb-port-names.rules
if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi
