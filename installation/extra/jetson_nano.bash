#!/bin/bash
set -euo pipefail

bash ./installation/modules/installation_common.bash

sudo mkdir -p /opt/blitz/
sudo chmod -R a+rw /opt/blitz/

bash ./installation/modules/installation_blitz.bash
bash ./installation/modules/installation_autobahn.bash


#### STARTUP
sudo mv ./installation/system-patch/blitzprojstartup.bash /usr/local/bin/
sudo chmod +x /usr/local/bin/blitzprojstartup.bash
echo "sudo /usr/local/bin/blitzprojstartup.bash" | sudo tee -a /etc/bash.bashrc
# bash ./installation/modules/install_startup.bash
#### END STARTUP


#### USB PORT NAMING
sudo rm -f /etc/udev/rules.d/90-usb-port-names.rules
sudo cp ./installation/system-patch/90-usb-port-names-jetson.rules /etc/udev/rules.d/90-usb-port-names.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
#### END USB PORT NAMING


sudo chmod -R a+rw /opt/blitz/

mkdir -p ~/.config/autostart

cat <<'EOF' > ~/.config/autostart/terminal.desktop
[Desktop Entry]
Type=Application
Name=Terminal
Exec=gnome-terminal --window --full-screen
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF

sudo reboot