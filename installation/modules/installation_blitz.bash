#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="/opt/blitz"
DEFAULT_PI_NAME="blitz-pi-random-name-1234"

TARGET_NAME="$DEFAULT_PI_NAME" \
TARGET_FOLDER="$INSTALLATION_DIR" \
SERVICE_NAME="blitz-startup" \
BLITZ_ASSUME_YES=true \
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/PinewoodRobotics/B.L.I.T.Z/HEAD/scripts/ui/install_on_system.sh)"
