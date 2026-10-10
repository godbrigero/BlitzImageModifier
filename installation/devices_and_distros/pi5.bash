#!/bin/bash
set -euo pipefail

BLITZ_DEVICE=pi5 BLITZ_PYTHON_SYSTEM_PACKAGES=true \
bash /workspace/installation/modules/main_startup.bash

sudo rm -f /etc/udev/rules.d/90-usb-port-names.rules
sudo cp ./installation/system-patch/90-usb-port-names.rules /etc/udev/rules.d/90-usb-port-names.rules
# The copied rule is picked up at boot; only reload on a running target.
if systemctl is-system-running >/dev/null 2>&1; then
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi
