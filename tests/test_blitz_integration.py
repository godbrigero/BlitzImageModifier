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
ln -s "$TEST_PYTHON" "$root/.venv/bin/python"
''')
    # A machine identity in the local checkout must not leak into the image.
    (source / "system_data/name.txt").write_text("developer-machine")
    destination = tmp_path / "installed with spaces"
    environment = dict(os.environ, BLITZ_SOURCE_DIR=str(source),
        BLITZ_INSTALLATION_DIR=str(destination), BLITZ_USER="robot", TEST_PYTHON=sys.executable)
    if mode == "system-packages":
        tools = tmp_path / "tools"
        tools.mkdir()
        python = tools / "python3"
        python.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$TEST_VENV_LOG"\n')
        python.chmod(0o755)
        environment.update(PATH=f'{tools}:{os.environ["PATH"]}', BLITZ_PYTHON_SYSTEM_PACKAGES="true", TEST_VENV_LOG=str(tmp_path / "venv-command"))
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


def test_rejects_source_without_updated_api(tmp_path):
    source = tmp_path / "incomplete"
    source.mkdir()
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_blitz.bash")],
        env=dict(os.environ, BLITZ_SOURCE_DIR=str(source), BLITZ_INSTALLATION_DIR=str(tmp_path / "target")),
        capture_output=True, text=True)
    assert result.returncode != 0
    assert "complete BLITZ source tree" in result.stderr
