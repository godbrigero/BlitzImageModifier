#!/bin/bash
set -euo pipefail

sudo mv ./installation/system-patch/blitzprojstartup.bash /usr/local/bin/
sudo chmod +x /usr/local/bin/blitzprojstartup.bash

echo "sudo /usr/local/bin/blitzprojstartup.bash" >> /etc/bash.bashrc