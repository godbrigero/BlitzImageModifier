#!/usr/bin/env python3
from __future__ import annotations

import ipaddress
import json
import subprocess
import sys
import time
from dataclasses import dataclass

try:
    from zeroconf import ServiceInfo, Zeroconf
except ImportError as error:
    raise SystemExit(
        "Python package 'zeroconf' is required. Install it with: python3 -m pip install zeroconf"
    ) from error


SIM_LABEL = "blitz.simulation=true"
WATCHDOG_SERVICE_TYPE = "_watchdog._udp.local."
AUTOBAHN_SERVICE_TYPE = "_autobahn._udp.local."
WATCHDOG_SERVICE_PORT = 9999
BLITZ_PATH = "/opt/blitz/B.L.I.T.Z"
REFRESH_SECONDS = 5


@dataclass(frozen=True)
class SimNode:
    name: str
    host_ip: str
    watchdog_host_port: int
    autobahn_host_port: int
    discovery_properties: dict[str, str]

    @property
    def hostname(self) -> str:
        hostname = self.discovery_properties.get("hostname") or f"{self.name}.local"
        return f"{hostname.rstrip('.')}."

    @property
    def service_name(self) -> str:
        system_name = self.discovery_properties.get("system_name") or self.name
        return f"{system_name}.{WATCHDOG_SERVICE_TYPE}"

    @property
    def autobahn_service_name(self) -> str:
        return f"{self.name}-autobahn.{AUTOBAHN_SERVICE_TYPE}"


def run_json(command: list[str]) -> object:
    raw = subprocess.check_output(command, text=True)
    return json.loads(raw)


def docker_ps_names() -> list[str]:
    raw = subprocess.check_output(
        [
            "docker",
            "ps",
            "--filter",
            f"label={SIM_LABEL}",
            "--format",
            "{{.Names}}",
        ],
        text=True,
    )
    return sorted(name for name in raw.splitlines() if name)


def published_host_port(container: dict[str, object], container_port: str) -> int:
    network_settings = container.get("NetworkSettings", {})
    ports = network_settings.get("Ports", {}) if isinstance(network_settings, dict) else {}
    bindings = ports.get(container_port) if isinstance(ports, dict) else None
    if not bindings:
        raise ValueError(f"{container['Name']} does not publish {container_port}")

    binding = bindings[0]
    return int(binding["HostPort"])


def published_host_ip(container: dict[str, object], container_port: str) -> str:
    network_settings = container.get("NetworkSettings", {})
    ports = network_settings.get("Ports", {}) if isinstance(network_settings, dict) else {}
    bindings = ports.get(container_port) if isinstance(ports, dict) else None
    if not bindings:
        raise ValueError(f"{container['Name']} does not publish {container_port}")

    binding = bindings[0]
    host_ip = binding.get("HostIp") or "127.0.0.1"
    if host_ip == "0.0.0.0":
        return "127.0.0.1"
    return str(host_ip)


def container_discovery_properties(name: str) -> dict[str, str]:
    raw = subprocess.check_output(
        [
            "docker",
            "exec",
            name,
            "bash",
            "-lc",
            (
                f"cd {BLITZ_PATH} && ./.venv/bin/python - <<'PY'\n"
                "import json\n"
                "from watchdog.util.system import DiscoveredNetworkSystem\n"
                "print(json.dumps(DiscoveredNetworkSystem.collect().to_dict(), sort_keys=True))\n"
                "PY"
            ),
        ],
        text=True,
    )
    properties = json.loads(raw)
    if not isinstance(properties, dict):
        raise ValueError(f"{name} returned invalid discovery properties: {properties!r}")

    return {
        str(key): str(value)
        for key, value in properties.items()
        if value is not None
    }


def load_nodes() -> list[SimNode]:
    nodes: list[SimNode] = []
    for name in docker_ps_names():
        inspected = run_json(["docker", "inspect", name])
        if not isinstance(inspected, list) or not inspected:
            continue

        container = inspected[0]
        watchdog_host_port = published_host_port(container, "5000/tcp")
        autobahn_host_port = published_host_port(container, "8080/tcp")
        host_ip = published_host_ip(container, "5000/tcp")
        discovery_properties = container_discovery_properties(name)
        discovery_properties["hostname"] = discovery_properties.get("hostname") or f"{name}.local"
        discovery_properties["system_name"] = discovery_properties.get("system_name") or name
        discovery_properties["watchdog_port"] = str(watchdog_host_port)
        discovery_properties["autobahn_port"] = str(autobahn_host_port)

        nodes.append(
            SimNode(
                name=name,
                host_ip=host_ip,
                watchdog_host_port=watchdog_host_port,
                autobahn_host_port=autobahn_host_port,
                discovery_properties=discovery_properties,
            )
        )

    return nodes


def properties_for(node: SimNode) -> dict[str, str]:
    return dict(node.discovery_properties)


def service_info_for(node: SimNode) -> ServiceInfo:
    return ServiceInfo(
        WATCHDOG_SERVICE_TYPE,
        node.service_name,
        addresses=[ipaddress.IPv4Address(node.host_ip).packed],
        port=WATCHDOG_SERVICE_PORT,
        server=node.hostname,
        properties=properties_for(node),
    )


def autobahn_service_info_for(node: SimNode) -> ServiceInfo:
    return ServiceInfo(
        AUTOBAHN_SERVICE_TYPE,
        node.autobahn_service_name,
        addresses=[ipaddress.IPv4Address(node.host_ip).packed],
        port=node.autobahn_host_port,
        server=node.hostname,
        properties={
            "ip": node.host_ip,
            "port": str(node.autobahn_host_port),
            "container_port": "8080",
            "system_name": node.name,
        },
    )


def service_infos_for(node: SimNode) -> list[ServiceInfo]:
    return [service_info_for(node), autobahn_service_info_for(node)]


def advertised_key(node: SimNode) -> tuple[str, int, int, str, str]:
    properties_json = json.dumps(node.discovery_properties, sort_keys=True)
    return (
        node.name,
        node.watchdog_host_port,
        node.autobahn_host_port,
        node.host_ip,
        properties_json,
    )


def unregister_infos(zc: Zeroconf, infos: list[ServiceInfo]) -> None:
    for info in infos:
        try:
            zc.unregister_service(info)
        except Exception:
            pass


def main() -> int:
    try:
        nodes = load_nodes()
    except FileNotFoundError:
        print("docker is required for sim-mdns.", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"docker command failed: {error}", file=sys.stderr)
        return 1

    if not nodes:
        print("No running simulator containers found.", file=sys.stderr)
        return 1

    zc = Zeroconf()
    registered: dict[tuple[str, int, int, str, str], list[ServiceInfo]] = {}

    try:
        print("mDNS bridge is running. Press Ctrl+C to stop advertising.", flush=True)
        while True:
            try:
                nodes = load_nodes()
            except Exception as error:
                print(f"warning: could not refresh simulator containers: {error}", file=sys.stderr, flush=True)
                nodes = []

            active_keys = {advertised_key(node) for node in nodes}

            for key in list(registered):
                if key not in active_keys:
                    unregister_infos(zc, registered.pop(key))
                    print(f"stopped advertising {key[0]}", flush=True)

            for node in nodes:
                key = advertised_key(node)
                if key in registered:
                    continue

                infos = service_infos_for(node)
                for info in infos:
                    zc.register_service(info, cooperating_responders=True)
                registered[key] = infos
                print(
                    f"advertising {node.name}: {node.hostname.rstrip('.')} "
                    f"host_ip={node.host_ip} watchdog={node.watchdog_host_port} "
                    f"autobahn={node.autobahn_host_port}",
                    flush=True,
                )

            time.sleep(REFRESH_SECONDS)
    except KeyboardInterrupt:
        print("\nStopping mDNS bridge.", flush=True)
    finally:
        for infos in registered.values():
            unregister_infos(zc, infos)
        zc.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
