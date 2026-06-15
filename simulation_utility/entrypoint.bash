#!/bin/bash
set -euo pipefail

: "${BLITZ_SIM_NAME:?BLITZ_SIM_NAME is required. Example: docker run -e BLITZ_SIM_NAME=blitz-sim-1 ...}"

if [[ ! "$BLITZ_SIM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "BLITZ_SIM_NAME can only contain letters, numbers, underscores, or hyphens." >&2
    exit 1
fi

NAME_PATH="/opt/blitz/B.L.I.T.Z/system_data/name.txt"
mkdir -p "$(dirname "$NAME_PATH")"
printf '%s\n' "$BLITZ_SIM_NAME" > "$NAME_PATH"

printf '%s\n' "$BLITZ_SIM_NAME" > /etc/hostname
hostname "$BLITZ_SIM_NAME" 2>/dev/null || true

if ! grep -qE "^127[.]0[.]1[.]1[[:space:]]+$BLITZ_SIM_NAME([[:space:]]|$)" /etc/hosts; then
    printf '127.0.1.1 %s\n' "$BLITZ_SIM_NAME" >> /etc/hosts || true
fi

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

exec /sbin/init
