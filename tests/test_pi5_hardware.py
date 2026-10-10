from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def test_boot_interface_settings_preserve_config_and_are_idempotent(tmp_path):
    spec = importlib.util.spec_from_file_location('pi5_config', ROOT / 'installation/util/configure_pi5_boot.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    path = tmp_path / 'config.txt'
    original = '# Existing camera choice\ncamera_auto_detect=0\n[pi5]\ndtoverlay=vc4-kms-v3d\n'
    path.write_text(original)
    module.configure_boot_config(path)
    first = path.read_text()
    module.configure_boot_config(path)
    assert path.read_text() == first
    assert original in first
    assert first.count(module.BEGIN) == 1
    assert '[all]\ncamera_auto_detect=1\ndtparam=i2c_arm=on\ndtparam=spi=on' in first


def test_hardware_provisioning_grants_service_groups_and_restricts_nodes(tmp_path):
    tools = tmp_path / 'bin'
    tools.mkdir()
    log = tmp_path / 'commands.log'
    for name in ('sudo', 'apt-get', 'getent', 'groupadd', 'usermod'):
        command = tools / name
        command.write_text('''#!/bin/bash
set -eu
name=$(basename "$0")
if [ "$name" = sudo ]; then exec "$@"; fi
printf '%s %s\\n' "$name" "$*" >> "$TEST_LOG"
if [ "$name" = getent ]; then exit 1; fi
''')
        command.chmod(0o755)
    python = tools / 'python3'
    python.symlink_to(sys.executable)
    image = tmp_path / 'image'
    (image / 'boot/firmware').mkdir(parents=True)
    (image / 'boot/firmware/config.txt').write_text('[all]\n')
    result = subprocess.run(['bash', str(ROOT / 'installation/modules/installation_pi5_hardware.bash')],
        env=dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}', BLITZ_HARDWARE_ROOT=str(image), BLITZ_USER='robot', TEST_LOG=str(log)),
        capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    commands = log.read_text()
    for group in ('gpio', 'i2c', 'spi', 'video', 'render'):
        assert f'usermod -aG {group} robot' in commands
    assert 'python3-picamera2' in commands and 'python3-libcamera' in commands
    assert 'python3-lgpio' in commands and 'rpicam-apps-lite' in commands
    rules = (image / 'etc/udev/rules.d/99-blitz-pi5-hardware.rules').read_text()
    assert 'MODE="0666"' not in rules
    assert 'GROUP="gpio", MODE="0660"' in rules
    assert 'SUBSYSTEM=="dma_heap", GROUP="video"' in rules
    assert (image / 'etc/modules-load.d/blitz-pi5.conf').read_text() == 'i2c-dev\n'


def test_pi_python_installs_binary_jpeg_compatibility_during_provisioning(tmp_path):
    install = tmp_path / 'install'
    executable = install / 'B.L.I.T.Z/.venv/bin/python'
    executable.parent.mkdir(parents=True)
    log = tmp_path / 'pip-arguments'
    executable.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$TEST_LOG"\n')
    executable.chmod(0o755)
    subprocess.run(['bash', str(ROOT / 'installation/modules/installation_pi5_python.bash')],
        env=dict(os.environ, BLITZ_INSTALLATION_DIR=str(install), TEST_LOG=str(log)), check=True)
    args = log.read_text().splitlines()
    assert args[:3] == ['-m', 'pip', 'install']
    assert '--only-binary=:all:' in args
    assert '--no-deps' in args  # Keep BLITZ's selected NumPy version intact.
    assert 'simplejpeg==1.9.0' in args
