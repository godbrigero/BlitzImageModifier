import importlib.util
import io
import json
from pathlib import Path
from urllib.error import URLError

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("watchdog_http_check", ROOT / "installation/util/check_watchdog_http.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def catalog(**overrides):
    from backend.deployment.network_api.catalog import SystemCatalog

    profile = SystemCatalog("jetson.local", "jetson", 5000, 8080, "/blitz", "aarch64", "Linux-glibc2.39", 3, 12, "ubuntu", None, "24.04")
    payload = profile.to_payload()
    payload["system"].update(overrides)
    return payload


def test_waits_for_startup_then_verifies_root_and_name(monkeypatch, tmp_path):
    calls = []

    def open_identity(url, timeout):
        calls.append(url)
        if len(calls) == 1:
            raise URLError("starting")
        payload = catalog(blitz_path=str(tmp_path), system_name="jetson")
        return io.BytesIO(json.dumps(payload).encode())

    monkeypatch.setattr(checker, "urlopen", open_identity)
    monkeypatch.setattr(checker.time, "sleep", lambda _: None)
    checker.wait_for_catalog(tmp_path, 5050, "jetson")
    assert calls == ["http://127.0.0.1:5050/get/system/catalog"] * 2


@pytest.mark.parametrize("identity", [
    {"blitz_path": "/another-root", "system_name": "jetson"},
    {"blitz_path": ".", "system_name": "another-device"},
])
def test_rejects_wrong_service_identity(monkeypatch, identity):
    monkeypatch.setattr(checker, "urlopen", lambda *args, **kwargs: io.BytesIO(json.dumps(catalog(**identity)).encode()))
    with pytest.raises(RuntimeError, match="different"):
        checker.wait_for_catalog(Path.cwd(), 5000, "jetson")


def test_unavailable_service_fails_with_cause(monkeypatch, tmp_path):
    def unavailable(*args, **kwargs):
        raise URLError("connection refused")

    monkeypatch.setattr(checker, "urlopen", unavailable)
    with pytest.raises(RuntimeError, match="connection refused"):
        checker.wait_for_catalog(tmp_path, 5000, "jetson", timeout=0)


@pytest.mark.parametrize("payload", [[], {"schema_version": 2, "system": {}}, {"schema_version": 3, "system": []}, {"blitz_path": "/blitz", "system_name": "jetson"}])
def test_invalid_catalog_fails_clearly(monkeypatch, tmp_path, payload):
    monkeypatch.setattr(checker, "urlopen", lambda *args, **kwargs: io.BytesIO(json.dumps(payload).encode()))
    with pytest.raises(RuntimeError, match="catalog|capabilities"):
        checker.wait_for_catalog(tmp_path, 5000, "jetson", timeout=0)
