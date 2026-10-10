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


def test_waits_for_startup_then_verifies_root_and_name(monkeypatch, tmp_path):
    calls = []

    def open_identity(url, timeout):
        calls.append(url)
        if len(calls) == 1:
            raise URLError("starting")
        return io.BytesIO(json.dumps({"blitz_path": str(tmp_path), "system_name": "jetson"}).encode())

    monkeypatch.setattr(checker, "urlopen", open_identity)
    monkeypatch.setattr(checker.time, "sleep", lambda _: None)
    checker.wait_for_identity(tmp_path, 5050, "jetson")
    assert calls == ["http://127.0.0.1:5050/get/system/identity"] * 2


@pytest.mark.parametrize("identity", [
    {"blitz_path": "/another-root", "system_name": "jetson"},
    {"blitz_path": ".", "system_name": "another-device"},
])
def test_rejects_wrong_service_identity(monkeypatch, identity):
    monkeypatch.setattr(checker, "urlopen", lambda *args, **kwargs: io.BytesIO(json.dumps(identity).encode()))
    with pytest.raises(RuntimeError, match="different"):
        checker.wait_for_identity(Path.cwd(), 5000, "jetson")


def test_unavailable_service_fails_with_cause(monkeypatch, tmp_path):
    def unavailable(*args, **kwargs):
        raise URLError("connection refused")

    monkeypatch.setattr(checker, "urlopen", unavailable)
    with pytest.raises(RuntimeError, match="connection refused"):
        checker.wait_for_identity(tmp_path, 5000, "jetson", timeout=0)
