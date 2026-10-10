"""Exercise Bookworm's real NetworkManager profiles and offline DHCP/bridge traffic."""
from pathlib import Path
import shutil
import subprocess
import uuid

import pytest

ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def test_bookworm_profiles_and_offline_ethernet_dhcp():
    if not shutil.which("docker") or subprocess.run(["docker", "info"], capture_output=True).returncode:
        pytest.skip("Docker is required for the real NetworkManager router test")
    name = "blitz-router-test-" + uuid.uuid4().hex[:10]
    image = name + ":latest"
    try:
        run(["docker", "build", "-q", "-f", str(ROOT / "tests/Dockerfile.router"), "-t", image, str(ROOT)])
        run(["docker", "run", "--privileged", "--name", name, "-d",
             "-e", "BLITZ_ROUTER_PASSWORD=test-password-only", "-e", "BLITZ_ROUTER_SSID=BLITZ test LAN",
             "-e", "BLITZ_ROUTER_LAN_INTERFACES=lan0", image])
        run(["docker", "exec", name, "python3", "/configure_pi5_router.py"])
        run(["docker", "exec", name, "python3", "-c", '''
from pathlib import Path
import configparser
root = Path('/etc/NetworkManager/system-connections')
profiles = {}
for path in root.glob('blitz-router-*.nmconnection'):
    assert path.stat().st_mode & 0o777 == 0o600
    config = configparser.ConfigParser(interpolation=None)
    config.read(path)
    profiles[config['connection']['id']] = config
bridge = profiles['blitz-router-lan']
assert bridge['ipv4']['method'] == 'shared'
assert bridge['ipv4']['address1'] == '10.42.0.1/24'
for name in ('blitz-router-wifi', 'blitz-router-ethernet-0'):
    assert profiles[name]['connection']['master'] == bridge['connection']['uuid']
wifi = profiles['blitz-router-wifi']
assert wifi['wifi']['ssid'] == 'BLITZ test LAN'
assert wifi['wifi']['mode'] == 'ap'
assert wifi['wifi']['ap-isolation'] == '0'
assert wifi['wifi-security']['key-mgmt'] == 'wpa-psk'
assert wifi['wifi-security']['psk'] == 'test-password-only'
'''])
        run(["docker", "exec", name, "sh", "-c", "mkdir -p /run/dbus; dbus-daemon --system; /usr/sbin/NetworkManager --no-daemon >/tmp/nm.log 2>&1 &"])
        result = run(["docker", "exec", name, "sh", "-c", '''
set -eu
for attempt in $(seq 1 30); do nmcli general status >/dev/null 2>&1 && break; sleep 1; done
nmcli connection reload
nmcli --wait 15 connection up blitz-router-lan
ip netns add jetson
ip link add lan0 type veth peer name client0
ip link set client0 netns jetson
ip netns exec jetson ip link set lo up
ip netns exec jetson ip link set client0 up
# NM intentionally excludes synthetic veth ports. Attach this simulated cable
# directly; the generated physical Ethernet profile is validated above.
ip link set lan0 master blitz-lan
ip link set lan0 up
# Prove DHCP and local traffic without an upstream route.
ip route del default
ip netns exec jetson timeout 25 dhclient -1 client0
ip netns exec jetson ip -4 address show client0
ip netns exec jetson ping -c 2 10.42.0.1
'''])
        assert "inet 10.42.0." in result
        assert "2 received" in result
    finally:
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)
        subprocess.run(["docker", "image", "rm", image], capture_output=True)
