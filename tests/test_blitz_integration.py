from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import uuid

import pytest

ROOT = Path(__file__).resolve().parents[1]
BLITZ = Path(os.environ.get("BLITZ_SOURCE_DIR", ROOT.parent / "BLITZ"))


def test_post_provisioning_validation_preserves_login_user_ownership():
    """Run with BLITZ_SIM_TEST_IMAGE=<built simulator image> and Docker."""
    image = os.environ.get("BLITZ_SIM_TEST_IMAGE")
    if not image:
        pytest.skip("Set BLITZ_SIM_TEST_IMAGE to run the real image ownership regression")
    name = "blitz-ownership-test-" + uuid.uuid4().hex[:10]
    def docker(*args):
        return subprocess.check_output(["docker", *args], text=True, stderr=subprocess.STDOUT, timeout=120)
    try:
        docker("run", "-d", "--name", name, "--entrypoint", "/bin/sleep", image, "180")
        docker("cp", str(ROOT / "installation"), f"{name}:/tmp/ownership-installation")
        # Force fresh imports after provisioning, instead of reusing the image's
        # existing bytecode. Only this disposable container is modified.
        docker("exec", name, "bash", "-c", '''set -e
bash /tmp/ownership-installation/modules/finalize_permissions.bash
find /opt/blitz/B.L.I.T.Z/backend/deployment /opt/blitz/B.L.I.T.Z/watchdog -type d -name __pycache__ -prune -exec rm -rf {} +
bash /tmp/ownership-installation/modules/validate_image.bash
test -d /opt/blitz/B.L.I.T.Z/watchdog/routes/__pycache__
''')
        foreign = docker("exec", name, "find", "/opt/blitz/B.L.I.T.Z", "!", "-user", "ubuntu", "-print", "-quit")
        assert not foreign.strip(), foreign
        docker("exec", name, "touch", "/opt/blitz/B.L.I.T.Z/backend/root-owned-regression-file")
        invalid = subprocess.run(["docker", "exec", name, "bash", "/tmp/ownership-installation/modules/validate_image.bash"], capture_output=True, text=True, timeout=120)
        assert invalid.returncode != 0
        assert "not owned by ubuntu" in invalid.stderr
    finally:
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)


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
    (installed / "backend/deployment/.blitz-build-version").write_text("3.0.0\n")
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
    assert "BLITZ 3.0.0 or later" in result.stderr
    assert (installed / "scripts/install.sh").read_text() == "exit 99\n"
