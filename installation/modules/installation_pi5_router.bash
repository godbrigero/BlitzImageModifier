#!/bin/bash
# Prepare at install time; activation at reboot avoids severing the install session.
set -euo pipefail
case "${BLITZ_ROUTER_ENABLED:-false}" in
    false) exit 0 ;;
    true) ;;
    *) echo 'BLITZ_ROUTER_ENABLED must be true or false.' >&2; exit 1 ;;
esac
if [ "${BLITZ_DEVICE:-}" != pi5 ]; then
    echo 'Router mode is supported only on the Raspberry Pi 5 profile.' >&2
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO=()
if [ "$(id -u)" != 0 ]; then SUDO=(sudo); fi
# Validate before package installation or network configuration changes.
python3 "$SCRIPT_DIR/../util/configure_pi5_router.py" --validate-only
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y network-manager dnsmasq-base iptables iw rfkill wireless-regdb
"${SUDO[@]}" env \
    BLITZ_ROUTER_SSID="${BLITZ_ROUTER_SSID:-BLITZ}" \
    BLITZ_ROUTER_PASSWORD="${BLITZ_ROUTER_PASSWORD:-}" \
    BLITZ_ROUTER_WIFI_INTERFACE="${BLITZ_ROUTER_WIFI_INTERFACE:-wlan0}" \
    BLITZ_ROUTER_LAN_INTERFACES="${BLITZ_ROUTER_LAN_INTERFACES:-eth0}" \
    BLITZ_ROUTER_ADDRESS="${BLITZ_ROUTER_ADDRESS:-10.42.0.1/24}" \
    BLITZ_ROUTER_COUNTRY="${BLITZ_ROUTER_COUNTRY:-US}" \
    python3 "$SCRIPT_DIR/../util/configure_pi5_router.py"
# Set the regulatory domain before NetworkManager starts the access point.
# Unlike raspi-config's live commands, this also works when preparing an image.
unit="$(mktemp)"
trap 'rm -f "$unit"' EXIT
cat > "$unit" <<EOF
[Unit]
Description=BLITZ router Wi-Fi regulatory domain
Before=NetworkManager.service
After=systemd-udev-trigger.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw reg set ${BLITZ_ROUTER_COUNTRY:-US}
ExecStart=/usr/sbin/rfkill unblock wifi
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
"${SUDO[@]}" install -m 0644 "$unit" /etc/systemd/system/blitz-router-regdomain.service
"${SUDO[@]}" systemctl enable blitz-router-regdomain.service
"${SUDO[@]}" systemctl enable NetworkManager
printf '%s\n' 'Router profiles installed. Reboot to activate Wi-Fi and Ethernet LAN.' \
    'NetworkManager supplies DHCP/DNS and shares an existing separate upstream connection.'
