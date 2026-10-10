"""Router configuration validation and preservation of existing network profiles."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("pi5_router", ROOT / "installation/util/configure_pi5_router.py")
router = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = router
SPEC.loader.exec_module(router)


@pytest.fixture
def environment(monkeypatch):
    for key in tuple(os.environ):
        if key.startswith("BLITZ_ROUTER_"):
            monkeypatch.delenv(key)
    monkeypatch.setenv("BLITZ_ROUTER_PASSWORD", "test-password-only")
    return monkeypatch


@pytest.mark.parametrize("key,value", [
    ("SSID", ""), ("SSID", "é" * 17), ("PASSWORD", "short"), ("PASSWORD", "x" * 64),
    ("PASSWORD", "bad\npassword"), ("WIFI_INTERFACE", "eth0"), ("LAN_INTERFACES", ""),
    ("LAN_INTERFACES", "eth0 eth0"), ("LAN_INTERFACES", "../eth0"),
    ("ADDRESS", "127.0.0.1/24"), ("ADDRESS", "8.8.8.1/24"), ("ADDRESS", "10.0.0.0/24"),
    ("ADDRESS", "192.168.0.255/24"), ("ADDRESS", "10.0.0.1/31"), ("COUNTRY", "US; reboot"),
])
def test_invalid_settings_are_rejected(environment, key, value):
    environment.setenv("BLITZ_ROUTER_" + key, value)
    with pytest.raises(ValueError):
        router.RouterSettings.from_environment()


def test_router_config_preserves_other_networks_and_retires_only_owned_ports(tmp_path):
    user = tmp_path / "home-wifi.nmconnection"
    user.write_text("existing user network")
    similarly_named = tmp_path / "blitz-router-ethernet-user.nmconnection"
    similarly_named.write_text("user network")
    stale = tmp_path / "blitz-router-ethernet-1.nmconnection"
    stale.write_text("old port")
    profiles = {"blitz-router-lan.nmconnection": "bridge", "blitz-router-ethernet-0.nmconnection": "port"}
    router.write_profiles(profiles, tmp_path)
    first = (tmp_path / "blitz-router-lan.nmconnection").stat().st_mtime_ns
    router.write_profiles(profiles, tmp_path)
    assert (tmp_path / "blitz-router-lan.nmconnection").stat().st_mtime_ns == first
    assert (tmp_path / "blitz-router-lan.nmconnection").stat().st_mode & 0o777 == 0o600
    assert user.read_text() == "existing user network"
    assert similarly_named.read_text() == "user network"
    assert not stale.exists()


def test_nmcli_failure_does_not_expose_password(environment, monkeypatch):
    settings = router.RouterSettings.from_environment()
    monkeypatch.setattr(router.subprocess, "run", lambda *args, **kwargs: subprocess.CompletedProcess([], 1, "", settings.password))
    with pytest.raises(RuntimeError) as error:
        router.generate_profiles(settings)
    assert settings.password not in str(error.value)
    assert "[redacted]" in str(error.value)


def test_offline_nmcli_bridge_warning_does_not_corrupt_keyfiles(environment, monkeypatch):
    monkeypatch.setattr(router.subprocess, "run", lambda *args, **kwargs: subprocess.CompletedProcess(
        [], 0, "Warning: bridge UUID does not refer to an existing profile.\n[connection]\nid=test\n", ""))
    profiles = router.generate_profiles(router.RouterSettings.from_environment())
    assert len(profiles) == 3
    assert all(content.startswith("[connection]\n") for content in profiles.values())


def test_disabled_router_changes_nothing(tmp_path):
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_pi5_router.bash")],
        env=dict(os.environ, BLITZ_ROUTER_ENABLED="false", PATH=str(tmp_path)),
        executable="/bin/bash", capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout == ""


def test_router_rejects_non_pi_profile():
    result = subprocess.run(["bash", str(ROOT / "installation/modules/installation_pi5_router.bash")],
        env=dict(os.environ, BLITZ_ROUTER_ENABLED="true", BLITZ_DEVICE="jetson"), capture_output=True, text=True)
    assert result.returncode != 0
    assert "only on the Raspberry Pi 5" in result.stderr
