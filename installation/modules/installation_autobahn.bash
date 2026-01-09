#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="/opt/blitz"

cd "$INSTALLATION_DIR"

git clone https://github.com/PinewoodRobotics/autobahn.git

cd autobahn

bash ./scripts/install.sh