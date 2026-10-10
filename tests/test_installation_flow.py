"""Check shared stage ordering, interpreter policy, and image safety failures."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


def tool(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
    path.chmod(0o755)


@pytest.mark.parametrize("device,image,state", [
    ("pi5", True, "offline"), ("pi5", False, "running"),
    ("jetson", False, "degraded"), ("linux", False, "running"),
])
def test_shared_pipeline_orders_provisioning_before_validation(tmp_path, device, image, state):
    tools = tmp_path / "bin"
    tools.mkdir()
    log = tmp_path / "log"
    tool(tools, "bash", 'printf "stage %s\\n" "$(basename "$1")" >> "$TEST_LOG"')
    tool(tools, "sudo", 'printf "sudo %s\\n" "$*" >> "$TEST_LOG"; exec "$@"')
    tool(tools, "chown", 'exit 0')
    tool(tools, "id", '''case "$1" in
      -un|-gn) echo robot ;;
      -u) if [ "$TEST_IMAGE" = true ]; then echo 0; else echo 1000; fi ;;
      *) echo robot ;;
    esac''')
    tool(tools, "systemctl", '''printf "systemctl %s\\n" "$*" >> "$TEST_LOG"
if [ "$1" = is-system-running ]; then echo "$TEST_STATE"; [ "$TEST_STATE" = running ]; fi''')
    result = subprocess.run(["/bin/bash", str(ROOT / "installation/modules/main_startup.bash")],
        cwd=tmp_path, env=dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
            TEST_LOG=str(log), TEST_IMAGE=str(image).lower(), TEST_STATE=state,
            BLITZ_IMAGE_BUILD=str(image).lower(), BLITZ_DEVICE=device,
            BLITZ_INSTALLATION_DIR=str(tmp_path / "installed"), BLITZ_USER="robot"),
        capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    lines = log.read_text().splitlines()
    stages = [line.removeprefix("stage ") for line in lines if line.startswith("stage ")]
    assert ("provision_user.bash" in stages) == image
    assert ("installation_pi5_hardware.bash" in stages) == (device == "pi5")
    assert ("installation_pi5_python.bash" in stages) == (device == "pi5")
    assert stages.index("installation_common.bash") < stages.index("installation_blitz.bash")
    assert stages.index("installation_blitz.bash") < stages.index("finalize_permissions.bash")
    assert stages.index("install_device_rules.bash") < stages.index("validate_image.bash")
    assert stages[-1] == "validate_image.bash"
    if state in ("running", "degraded"):
        assert lines.index("stage finalize_permissions.bash") < lines.index("systemctl restart autobahn blitz-startup") < lines.index("stage validate_image.bash")


@pytest.mark.parametrize("device,mode", [("pi5", "managed"), ("jetson", "managed"), ("linux", "system")])
def test_common_python_policy_reuses_toolchains_without_global_pip(tmp_path, device, mode):
    tools = tmp_path / "bin"
    tools.mkdir()
    home = tmp_path / "home"
    (home / ".cargo/bin").mkdir(parents=True)
    (home / ".cargo/bin/rustc").write_text("#!/bin/bash\n")
    (home / ".cargo/bin/rustc").chmod(0o755)
    (home / ".cargo/env").write_text("")
    (home / ".pyenv/bin").mkdir(parents=True)
    tool(home / ".pyenv/bin", "pyenv", 'printf "pyenv %s\\n" "$*" >> "$TEST_LOG"')
    log = tmp_path / "log"
    tool(tools, "sudo", 'exec "$@"')
    tool(tools, "apt-get", 'printf "apt %s\\n" "$*" >> "$TEST_LOG"')
    tool(tools, "systemctl", 'if [ "$1" = is-system-running ]; then exit 1; fi')
    tool(tools, "curl", 'echo "unexpected download" >&2; exit 99')
    tool(tools, "pip", 'echo "unexpected global pip" >&2; exit 99')
    result = subprocess.run(["/bin/bash", str(ROOT / "installation/modules/installation_common.bash")],
        env=dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", HOME=str(home),
                 TEST_LOG=str(log), BLITZ_DEVICE=device, BLITZ_PYTHON_MODE=mode),
        capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    output = log.read_text()
    assert ("pyenv install --skip-existing 3.12.6" in output) == (device == "jetson")
    assert "python3-venv" in output


def test_image_download_failure_does_not_poison_cache(tmp_path):
    tools = tmp_path / "bin"
    tools.mkdir()
    tool(tools, "wget", 'printf "partial" > "$2"; exit 8')
    cache = tmp_path / "cache"
    result = subprocess.run(["bash", str(ROOT / "installation/util/install_distro.bash"), "os.img", "https://example.invalid/os.xz"],
        env=dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                 BLITZ_IMAGE_CACHE=str(cache), BLITZ_WORKSPACE=str(tmp_path / "workspace")),
        capture_output=True, text=True)
    assert result.returncode == 8
    assert list(cache.iterdir()) == []


def test_export_refuses_busy_mount_before_copy(tmp_path):
    tools = tmp_path / "bin"
    tools.mkdir()
    tool(tools, "losetup", 'echo "/dev/loop99: test.img"')
    tool(tools, "sync", 'exit 0')
    tool(tools, "mountpoint", 'exit 0')
    tool(tools, "umount", 'echo "busy filesystem" >&2; exit 32')
    output = tmp_path / "outputs"
    result = subprocess.run(["bash", str(ROOT / "export_image_and_compress.bash"), "test.img", "pi5", "false"],
        env=dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", BLITZ_OUTPUT_DIR=str(output)),
        capture_output=True, text=True)
    assert result.returncode == 32
    assert not output.exists()


@pytest.mark.parametrize("device,rule", [("pi5", "90-usb-port-names.rules"), ("jetson", "90-usb-port-names-jetson.rules")])
@pytest.mark.parametrize("state", ["running", "degraded", "offline"])
def test_usb_rules_are_installed_and_live_udev_is_reloaded(tmp_path, device, rule, state):
    tools = tmp_path / "bin"
    tools.mkdir()
    log = tmp_path / "log"
    installed = tmp_path / "installed.rules"
    tool(tools, "sudo", '''printf "sudo %s\\n" "$*" >> "$TEST_LOG"
if [ "$1" = install ]; then cp "$4" "$TEST_RULE"; chmod "$3" "$TEST_RULE"; else exec "$@"; fi''')
    tool(tools, "systemctl", 'echo "$TEST_STATE"; [ "$TEST_STATE" = running ]')
    tool(tools, "udevadm", 'printf "udevadm %s\\n" "$*" >> "$TEST_LOG"')
    result = subprocess.run(["bash", str(ROOT / "installation/modules/install_device_rules.bash")],
        cwd=tmp_path, env=dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                 TEST_LOG=str(log), TEST_RULE=str(installed), TEST_STATE=state,
                 BLITZ_DEVICE=device), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert installed.read_bytes() == (ROOT / "installation/system-patch" / rule).read_bytes()
    assert installed.stat().st_mode & 0o777 == 0o644
    output = log.read_text()
    assert "/etc/udev/rules.d/90-usb-port-names.rules" in output
    assert ("udevadm control --reload-rules" in output) == (state != "offline")
    assert ("udevadm trigger" in output) == (state != "offline")


def test_startup_install_elevates_append_and_does_not_duplicate_or_move_source(tmp_path):
    tools = tmp_path / "bin"
    tools.mkdir()
    log = tmp_path / "log"
    bashrc = tmp_path / "bashrc"
    bashrc.write_text("# existing settings\n")
    tool(tools, "sudo", '''printf 'sudo %s\\n' "$*" >> "$TEST_LOG"
if [ "$1" != install ]; then exec "$@"; fi''')
    env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", TEST_LOG=str(log),
               BLITZ_BASHRC_PATH=str(bashrc))
    for _ in range(2):
        subprocess.run(["bash", str(ROOT / "installation/modules/install_startup.bash")],
                       env=env, check=True, capture_output=True)
    assert bashrc.read_text().count("sudo /usr/local/bin/blitzprojstartup.bash") == 1
    assert log.read_text().count("sudo tee -a") == 1
    assert (ROOT / "installation/system-patch/blitzprojstartup.bash").exists()
