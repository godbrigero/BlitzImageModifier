#!/bin/bash
set -euo pipefail

INSTALLATION_DIR="/opt/blitz"
NAME_PATH="$INSTALLATION_DIR/B.L.I.T.Z/system_data/name.txt"

if [ ! -f "$NAME_PATH" ]; then
    echo "name.txt not found at $NAME_PATH; creating it."
    mkdir -p "$(dirname "$NAME_PATH")"
    echo "blitz-pi-random-name-1234" | tee "$NAME_PATH" >/dev/null
fi

NAME=$(cat "$NAME_PATH")

if [ "$NAME" != "blitz-pi-random-name-1234" ]; then
    exit 0
fi

function get_name() {
    read -p "Enter a name for the Blitz Pi: " NEW_NAME
    if [[ "$NEW_NAME" =~ [^a-zA-Z0-9_-] ]]; then
        echo "Name can only contain letters, numbers, underscores, or hyphens. Try again."
        get_name
        return
    fi

    if [[ -z "$NEW_NAME" ]]; then
        echo "Name cannot be empty. Try again."
        get_name
        return
    fi

    echo "$NEW_NAME"
}

NEW_NAME=$(get_name)

echo "$NEW_NAME" | tee "$NAME_PATH" >/dev/null

hostnamectl set-hostname "$NEW_NAME"
grep -q "^127.0.1.1[[:space:]]\+$NEW_NAME$" /etc/hosts || echo "127.0.1.1 $NEW_NAME" | tee -a /etc/hosts >/dev/null
systemctl restart avahi-daemon
systemctl restart ssh

reboot