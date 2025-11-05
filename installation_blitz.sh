#!/bin/bash

INSTALLATION_DIR="/opt/blitz"
BRANCH_NAME="merge-backend"
DEFAULT_PI_NAME="blitz-pi-random-name-1234"

cd "$INSTALLATION_DIR"

git clone -b "$BRANCH_NAME" https://github.com/PinewoodRobotics/B.L.I.T.Z.git
cd B.L.I.T.Z
git submodule update --init --recursive

bash scripts/install.sh --name "$DEFAULT_PI_NAME"
