"""Generate NetworkManager's validated bridge/AP profiles without a live daemon."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import tempfile
import uuid


@dataclass(frozen=True)
class RouterSettings:
    ssid: str
    password: str
    wifi_interface: str
    lan_interfaces: tuple[str, ...]
    address: str
    country: str

    @classmethod
    def from_environment(cls) -> RouterSettings:
        settings = cls(
            os.environ.get("BLITZ_ROUTER_SSID", "BLITZ"),
            os.environ.get("BLITZ_ROUTER_PASSWORD", ""),
            os.environ.get("BLITZ_ROUTER_WIFI_INTERFACE", "wlan0"),
            tuple(os.environ.get("BLITZ_ROUTER_LAN_INTERFACES", "eth0").split()),
            os.environ.get("BLITZ_ROUTER_ADDRESS", "10.42.0.1/24"),
            os.environ.get("BLITZ_ROUTER_COUNTRY", "US"),
        )
        if not 1 <= len(settings.ssid.encode("utf-8")) <= 32 or "\x00" in settings.ssid:
            raise ValueError("BLITZ_ROUTER_SSID must contain 1–32 UTF-8 bytes")
        if not 8 <= len(settings.password) <= 63 or any(not 32 <= ord(c) <= 126 for c in settings.password):
            raise ValueError("BLITZ_ROUTER_PASSWORD must contain 8–63 printable ASCII characters")
        interfaces = (settings.wifi_interface, *settings.lan_interfaces)
        if not re.fullmatch(r"[A-Z]{2}", settings.country):
            raise ValueError("BLITZ_ROUTER_COUNTRY must be a two-letter country code")
        if not settings.lan_interfaces or len(set(interfaces)) != len(interfaces):
            raise ValueError("Wi-Fi and LAN interfaces must be distinct; provide at least one LAN interface")
        if any(not re.fullmatch(r"[A-Za-z0-9_-]{1,15}", value) or value in ("lo", "blitz-lan") for value in interfaces):
            raise ValueError("Invalid router interface name")
        address = ipaddress.IPv4Interface(settings.address)
        private_networks = [ipaddress.IPv4Network(value) for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
        if not any(address.network.subnet_of(network) for network in private_networks) or address.network.prefixlen > 29:
            raise ValueError("Router address must be a private LAN IPv4 subnet with room for DHCP clients")
        if address.ip in (address.network.network_address, address.network.broadcast_address):
            raise ValueError("Router address cannot be the network or broadcast address")
        return settings


def profile_uuid(name: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "blitz.local.router." + name))


def generate_profiles(settings: RouterSettings) -> dict[str, str]:
    bridge = profile_uuid("lan")
    common = ["connection.autoconnect", "yes", "connection.autoconnect-priority", "100"]
    definitions = {
        "blitz-router-lan": ["type", "bridge", "ifname", "blitz-lan", "connection.uuid", bridge,
            "connection.autoconnect-slaves", "1", "bridge.stp", "no",
            "ipv4.method", "shared", "ipv4.addresses", settings.address,
            "ipv4.never-default", "yes", "ipv6.method", "disabled"],
        "blitz-router-wifi": ["type", "wifi", "ifname", settings.wifi_interface,
            "master", bridge, "slave-type", "bridge", "ssid", settings.ssid,
            "802-11-wireless.mode", "ap", "802-11-wireless.band", "bg",
            "802-11-wireless.channel", "6", "802-11-wireless.ap-isolation", "0",
            "802-11-wireless-security.key-mgmt", "wpa-psk",
            "802-11-wireless-security.proto", "rsn", "802-11-wireless-security.pairwise", "ccmp",
            "802-11-wireless-security.group", "ccmp", "802-11-wireless-security.psk", settings.password],
    }
    for index, interface in enumerate(settings.lan_interfaces):
        definitions[f"blitz-router-ethernet-{index}"] = ["type", "ethernet", "ifname", interface,
            "master", bridge, "slave-type", "bridge"]
    profiles = {}
    for name, properties in definitions.items():
        if name != "blitz-router-lan":
            properties += ["connection.uuid", profile_uuid(name)]
        result = subprocess.run(["nmcli", "--offline", "connection", "add", "con-name", name,
            *properties, *common], capture_output=True, text=True, check=False)
        if result.returncode:
            detail = result.stderr.replace(settings.password, "[redacted]")
            raise RuntimeError(f"NetworkManager rejected {name}: {detail.strip()}")
        # Offline nmcli cannot resolve a bridge UUID against other profiles;
        # Bookworm emits that warning on stdout before the keyfile itself.
        start = result.stdout.find("[connection]\n")
        if start < 0:
            raise RuntimeError(f"NetworkManager did not produce a keyfile for {name}")
        profiles[name + ".nmconnection"] = result.stdout[start:]
    return profiles


def write_profiles(profiles: dict[str, str], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    for name, content in profiles.items():
        destination = output / name
        if destination.is_file() and destination.read_text() == content:
            destination.chmod(0o600)
            continue
        fd, temporary = tempfile.mkstemp(prefix=".blitz-router-", dir=output)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(content)
            os.replace(temporary, destination)
        finally:
            Path(temporary).unlink(missing_ok=True)
    # Retire only our own former Ethernet ports when the explicit LAN list shrinks.
    for path in output.glob("blitz-router-ethernet-*.nmconnection"):
        if re.fullmatch(r"blitz-router-ethernet-\d+\.nmconnection", path.name) and path.name not in profiles:
            path.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=Path("/etc/NetworkManager/system-connections"))
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    try:
        settings = RouterSettings.from_environment()
        if not args.validate_only:
            write_profiles(generate_profiles(settings), args.output_directory)
            print(f"Router profiles prepared: SSID {settings.ssid!r}, gateway {settings.address}, "
                  f"Wi-Fi {settings.wifi_interface}, Ethernet {' '.join(settings.lan_interfaces)}")
    except (ValueError, OSError, RuntimeError) as error:
        parser.exit(1, f"Router configuration failed: {error}\n")
