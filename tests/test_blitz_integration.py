from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
BLITZ = Path(os.environ.get("BLITZ_SOURCE_DIR", ROOT.parent / "BLITZ"))


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def test_simulator_discovery_matches_current_backend():
    sys.path.insert(0, str(BLITZ))
    from backend.deployment.network_api.zeroconf import DiscoveredNetworkSystem
    bridge = load_module("test_mdns_bridge", ROOT / "simulation_utility/mdns_bridge.py")
    properties = {
        "hostname": "jetson.local", "system_name": "jetson", "watchdog_port": "5000",
        "autobahn_port": "8080", "blitz_path": "/opt/blitz/B.L.I.T.Z",
        "machine_architecture": "aarch64", "platform_description": "Linux-glibc2.35",
        "python_major_version": "3", "python_minor_version": "10",
        "os_distribution_id": "ubuntu", "os_distribution_version_id": "22.04",
        "capabilities_json": json.dumps({"cuda": "12.2"}),
    }
    node = bridge.SimNode("jetson", "127.42.0.1", 5000, 8080, properties)
    discovered = DiscoveredNetworkSystem.from_service_info(bridge.service_info_for(node))
    assert discovered.blitz_path == properties["blitz_path"]
    assert discovered.watchdog_port == 5000
    assert discovered.to_system_id().capabilities == (("cuda", "12.2"),)


@pytest.mark.parametrize("mode", ["local", "git", "system-packages"])
def test_image_install_uses_selected_checkout_and_runtime_check(tmp_path, mode):
    source = tmp_path / "source"
    source.mkdir()
    subprocess.run([
        "rsync", "-a", "--exclude=.git", "--exclude=.venv", "--exclude=build",
        "--exclude=website", "--exclude=__pycache__", f"{BLITZ}/", str(source),
    ], check=True)
    # Exercise image orchestration without apt, systemd, or root modifications.
    installer = source / "scripts/ui/install_on_system.sh"
    installer.write_text('''#!/bin/bash
set -eu
[ "$DEV_LOCAL_OVERRIDE" = true ]
[ "$SERVICE_USER" = robot ]
root="$TARGET_FOLDER/B.L.I.T.Z"
mkdir -p "$root/.venv/bin" "$root/system_data"
printf '%s\\n' "$TARGET_NAME" > "$root/system_data/name.txt"
[ -x "$root/.venv/bin/protoc" ]
[ "$(command -v protoc)" = "$root/.venv/bin/protoc" ]
''')
    # A machine identity in the local checkout must not leak into the image.
    (source / "system_data/name.txt").write_text("developer-machine")
    destination = tmp_path / "installed with spaces"
    tools = tmp_path / "tools"
    tools.mkdir()
    runtime = tools / "venv-runtime"
    runtime.write_text('''#!/bin/bash
set -eu
if [ "$1" = -m ] && [ "$2" = pip ]; then
    printf '%s\\n' "$*" >> "$TEST_PIP_LOG"
    exit 0
fi
exec "$TEST_PYTHON" "$@"
''')
    runtime.chmod(0o755)
    python = tools / "venv-python"
    python.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$@" > "$TEST_VENV_LOG"
destination="${!#}"
mkdir -p "$destination/bin"
cp "$TEST_VENV_PYTHON_STUB" "$destination/bin/python"
chmod +x "$destination/bin/python"
''')
    python.chmod(0o755)
    environment = dict(os.environ, BLITZ_SOURCE_DIR=str(source),
        BLITZ_INSTALLATION_DIR=str(destination), BLITZ_USER="robot", TEST_PYTHON=sys.executable,
        BLITZ_PYTHON_BINARY=str(python), TEST_VENV_PYTHON_STUB=str(runtime),
        TEST_PIP_LOG=str(tmp_path / "pip-command"), TEST_VENV_LOG=str(tmp_path / "venv-command"))
    if mode == "system-packages":
        environment.update(BLITZ_PYTHON_SYSTEM_PACKAGES="true")
    if mode == "git":
        subprocess.run(["git", "init", str(source)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "test source"], check=True, capture_output=True)
        revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        environment.pop("BLITZ_SOURCE_DIR")
        environment.update(BLITZ_GIT_URL=str(source), BLITZ_REF=revision)
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "offline tools verified" in result.stdout
    assert "grpcio-tools" in (tmp_path / "pip-command").read_text()
    if mode == "system-packages":
        assert (tmp_path / "venv-command").read_text().splitlines() == ["-m", "venv", "--system-site-packages", str(destination / "B.L.I.T.Z/.venv")]
    assert (destination / "B.L.I.T.Z/system_data/name.txt").read_text().strip() == "blitz-pi-random-name-1234"
    # A stale deployment runtime must fail the post-install check.
    installed = destination / "B.L.I.T.Z"
    (installed / "backend/deployment/.blitz-build-version").write_text("1.0.21\n")
    stale = subprocess.run([sys.executable, str(ROOT / "installation/util/check_blitz_runtime.py")],
        env=dict(os.environ, BLITZ_PATH=str(installed)), capture_output=True, text=True)
    assert stale.returncode != 0
    assert "too old" in stale.stderr
    # Existing installations must not be silently overwritten.
    again = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=environment, capture_output=True, text=True)
    assert again.returncode != 0
    assert "already exists" in again.stderr
    # A Jetson retry uses the existing checkout and preserves its assigned name.
    (installed / "backend/deployment/.blitz-build-version").write_text("1.2.0\n")
    (installed / "system_data/name.txt").write_text("existing-jetson\n")
    resumed = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=dict(environment, BLITZ_RESUME_INSTALL="true"), capture_output=True, text=True)
    assert resumed.returncode == 0, resumed.stdout + resumed.stderr
    assert "Resuming" in resumed.stdout
    assert (installed / "system_data/name.txt").read_text().strip() == "existing-jetson"


def test_rejects_source_without_updated_api(tmp_path):
    source = tmp_path / "incomplete"
    source.mkdir()
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=dict(os.environ, BLITZ_SOURCE_DIR=str(source), BLITZ_INSTALLATION_DIR=str(tmp_path / "target")),
        capture_output=True, text=True)
    assert result.returncode != 0
    assert "complete BLITZ source tree" in result.stderr


def test_resume_rejects_old_checkout_without_running_installer(tmp_path):
    installed = tmp_path / "target/B.L.I.T.Z"
    (installed / "scripts").mkdir(parents=True)
    (installed / "scripts/install.sh").write_text("exit 99\n")
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=dict(os.environ, BLITZ_INSTALLATION_DIR=str(installed.parent),
                 BLITZ_RESUME_INSTALL="true"), capture_output=True, text=True)
    assert result.returncode != 0
    assert "missing scripts/ui/install_on_system.sh" in result.stderr
    assert "BLITZ 1.2.0 or later" in result.stderr
    assert (installed / "scripts/install.sh").read_text() == "exit 99\n"
