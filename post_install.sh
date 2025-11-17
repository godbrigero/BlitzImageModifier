#!/bin/bash
set -euo pipefail

sudo mv ./blitzprojstartup.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/blitzprojstartup.sh

echo "sudo /usr/local/bin/blitzprojstartup.sh" >> /etc/bash.bashrc