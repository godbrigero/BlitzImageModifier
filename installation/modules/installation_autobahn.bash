#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="${BLITZ_INSTALLATION_DIR:-/opt/blitz}"
cd "$INSTALLATION_DIR"
if [ ! -e autobahn ]; then
    git clone https://github.com/PinewoodRobotics/autobahn.git
elif [ ! -f autobahn/Cargo.toml ]; then
    echo "Existing $INSTALLATION_DIR/autobahn is not a Cargo project; refusing to overwrite it." >&2
    exit 1
fi
cd autobahn

# installation_common runs in another shell; load the toolchain here as well.
. "$HOME/.cargo/env"
cargo build --release
sudo install -m 0755 target/release/autobahn /usr/local/bin/autobahn
sudo install -m 0644 scripts/autobahn.service /etc/systemd/system/autobahn.service
sudo mkdir -p /etc/autobahn
if [ ! -e /etc/autobahn/config.toml ]; then
    sudo install -m 0644 config.toml /etc/autobahn/config.toml
fi
sudo systemctl enable autobahn
if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
    sudo systemctl daemon-reload
    sudo systemctl restart autobahn
fi
