#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="/opt/blitz"
cd "$INSTALLATION_DIR"
git clone https://github.com/PinewoodRobotics/autobahn.git
cd autobahn

# installation_common runs in another shell; load the toolchain here as well.
. "$HOME/.cargo/env"
cargo build --release
sudo install -m 0755 target/release/autobahn /usr/local/bin/autobahn
sudo install -m 0644 scripts/autobahn.service /etc/systemd/system/autobahn.service
sudo mkdir -p /etc/autobahn
sudo install -m 0644 config.toml /etc/autobahn/config.toml
sudo systemctl enable autobahn
if systemctl is-system-running >/dev/null 2>&1; then
    sudo systemctl daemon-reload
    sudo systemctl restart autobahn
fi
