from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


def commands(tmp_path: Path) -> Path:
    directory = tmp_path / 'bin'
    directory.mkdir()
    script = '''#!/bin/bash
set -eu
name=$(basename "$0")
printf '%s %s\\n' "$name" "$*" >> "$TEST_LOG"
case "$name" in
  losetup) if [ "$1" != -d ]; then echo /dev/loop99; fi ;;
  mountpoint) exit 1 ;;
  e2fsck) exit "$TEST_FSCK_STATUS" ;;
  chroot)
    case "$*" in
      *uname*) echo aarch64 ;;
      *os-release*) echo 'PRETTY_NAME="Raspberry Pi OS"' ;;
      *) exit "$TEST_CHROOT_STATUS" ;;
    esac ;;
  cp) if [ "$1" = /usr/bin/qemu-aarch64-static ]; then exit 0; fi
      exec /bin/cp "$@" ;;
esac
'''
    for name in ['losetup', 'sgdisk', 'parted', 'kpartx', 'e2fsck', 'resize2fs', 'lsblk', 'sleep', 'mount', 'mountpoint', 'umount', 'chroot', 'cp', 'hostnamectl', 'systemctl', 'reboot']:
        command = directory / name
        command.write_text(script)
        command.chmod(0o755)
    return directory


@pytest.mark.parametrize('fsck_status,chroot_status', [(0, 0), (1, 0), (2, 0), (4, 0), (0, 1)])
def test_bookworm_mounts_and_dns_restoration(tmp_path, fsck_status, chroot_status):
    tools = commands(tmp_path)
    target = tmp_path / 'root'
    (target / 'boot/firmware').mkdir(parents=True)
    (target / 'etc').mkdir()
    original = '/run/NetworkManager/resolv.conf'
    (target / 'etc/resolv.conf').symlink_to(original)
    log = tmp_path / 'commands.log'
    environment = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}',
        BLITZ_MOUNT_POINT=str(target), BLITZ_WORKSPACE=str(tmp_path),
        BLITZ_SOURCE_DIR='', TEST_LOG=str(log), TEST_FSCK_STATUS=str(fsck_status), TEST_CHROOT_STATUS=str(chroot_status))
    result = subprocess.run(['bash', str(ROOT / 'setup_image.bash'), 'test.img', 'installation/devices_and_distros/pi5.bash'],
        env=environment, capture_output=True, text=True)
    assert (target / 'etc/resolv.conf').is_symlink()
    assert os.readlink(target / 'etc/resolv.conf') == original
    if fsck_status > 2 or chroot_status:
        assert result.returncode != 0
        assert 'losetup -d /dev/loop99' in log.read_text()
    else:
        assert result.returncode == 0, result.stdout + result.stderr
        assert f'mount /dev/mapper/loop99p1 {target}/boot/firmware' in log.read_text()
        assert 'losetup -d' not in log.read_text()  # Export performs teardown on success.


def test_first_boot_invalid_input_does_not_pollute_name(tmp_path):
    tools = commands(tmp_path)
    root = tmp_path / 'install'
    name_file = root / 'B.L.I.T.Z/system_data/name.txt'
    name_file.parent.mkdir(parents=True)
    name_file.write_text('blitz-pi-random-name-1234\n')
    hosts = tmp_path / 'hosts'
    hosts.write_text('127.0.0.1 localhost\n')
    environment = dict(os.environ, PATH=f'{tools}:{os.environ["PATH"]}',
        BLITZ_INSTALLATION_DIR=str(root), BLITZ_HOSTS_PATH=str(hosts), TEST_LOG=str(tmp_path / 'commands.log'))
    result = subprocess.run(['bash', str(ROOT / 'installation/system-patch/blitzprojstartup.bash')],
        input='bad name\n\npi5-test\n', env=environment, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert name_file.read_text() == 'pi5-test\n'
    assert '127.0.1.1 pi5-test' in hosts.read_text()
    assert 'Try again' in result.stderr
