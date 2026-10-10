#!/bin/bash
set -euo pipefail

# Resolve paths from this file so invoking it outside the repository also works.
REPOSITORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPOSITORY_DIR"
export BLITZ_USER="${BLITZ_USER:-$(id -un)}"
if [ "$BLITZ_USER" = root ]; then
    echo "Run this script as your normal Jetson login user, without sudo." >&2
    exit 1
fi
export BLITZ_RESUME_INSTALL=true
export BLITZ_DEVICE=jetson
trap 'status=$?; echo "Jetson installation failed at line $LINENO (exit $status). Fix the reported error and rerun this script; existing BLITZ source is preserved." >&2; exit "$status"' ERR

bash ./installation/modules/main_startup.bash


mkdir -p ~/.config/autostart

cat <<'EOF' > ~/.config/autostart/terminal.desktop
[Desktop Entry]
Type=Application
Name=Terminal
Exec=gnome-terminal --window --full-screen
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF

if [ "${BLITZ_REBOOT:-true}" = true ]; then
    sudo reboot
else
    echo "Jetson setup completed. Reboot when ready."
fi
