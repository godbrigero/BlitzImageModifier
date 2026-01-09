#!/bin/bash
set -euo pipefail

bash /workspace/installation/modules/main_startup.bash

sudo rm -f /etc/udev/rules.d/90-usb-port-names.rules
sudo cp ./installation/system-patch/90-usb-port-names.rules /etc/udev/rules.d/90-usb-port-names.rules
sudo udevadm control --reload-rules
sudo udevadm trigger