#!/bin/bash
set -euo pipefail

BLITZ_USER="${BLITZ_USER:-ubuntu}"
INSTALLATION_DIR="/opt/blitz"

if ! getent passwd "$BLITZ_USER" >/dev/null; then
    echo "Cannot finalize permissions: user $BLITZ_USER does not exist." >&2
    exit 1
fi

if [ ! -d "$INSTALLATION_DIR" ]; then
    echo "Cannot finalize permissions: $INSTALLATION_DIR does not exist." >&2
    exit 1
fi

BLITZ_GROUP="$(id -gn "$BLITZ_USER")"

chown -R "$BLITZ_USER:$BLITZ_GROUP" "$INSTALLATION_DIR"
find "$INSTALLATION_DIR" -type d -exec chmod 2775 {} +
find "$INSTALLATION_DIR" -type f -exec chmod u+rw,g+rw {} +

echo "Finalized $INSTALLATION_DIR ownership for $BLITZ_USER:$BLITZ_GROUP."
