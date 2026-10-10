"""Exercise Jetson orchestration without touching host services or installing packages."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("fail_install", [False, True])
def test_jetson_uses_login_user_and_handles_partial_install(tmp_path: Path, fail_install: bool):
    tools = tmp_path / "tools"
    tools.mkdir()
    log = tmp_path / "commands"
    commands = {
        "id": 'echo jetson',
        "grep": 'exit 1',
        "sudo": 'printf "sudo %s\\n" "$*" >> "$TEST_LOG"',
        "bash": '''printf 'script %s user=%s resume=%s\\n' "$1" "$BLITZ_USER" "$BLITZ_RESUME_INSTALL" >> "$TEST_LOG"
if [[ "$1" == *main_startup.bash && "$TEST_FAIL_INSTALL" == true ]]; then exit 42; fi''',
    }
    for name, body in commands.items():
        path = tools / name
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)
    environment = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       HOME=str(tmp_path / "home"), TEST_LOG=str(log),
                       TEST_FAIL_INSTALL=str(fail_install).lower())
    environment.pop("BLITZ_USER", None)
    result = subprocess.run(["/bin/bash", str(ROOT / "installation/extra/jetson_nano.bash")],
                            cwd=tmp_path, env=environment, capture_output=True, text=True)
    output = log.read_text()
    assert "main_startup.bash user=jetson resume=true" in output
    if fail_install:
        assert result.returncode == 42
        assert "Jetson installation failed" in result.stderr
        assert "sudo reboot" not in output
    else:
        assert result.returncode == 0, result.stderr
        assert "sudo reboot" in output
        assert (tmp_path / "home/.config/autostart/terminal.desktop").exists()


def test_jetson_rejects_root_invocation(tmp_path: Path):
    result = subprocess.run(["bash", str(ROOT / "installation/extra/jetson_nano.bash")],
                            env=dict(os.environ, BLITZ_USER="root"),
                            capture_output=True, text=True)
    assert result.returncode != 0
    assert "normal Jetson login user" in result.stderr
