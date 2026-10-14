"""Exercise simulator source selection and the actual staged Docker context."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def build_tree(tmp_path):
    project = tmp_path / "BlitzImageModifier"
    simulation = project / "simulation_utility"
    simulation.mkdir(parents=True)
    for filename in ("Makefile", "build_image.bash", "Dockerfile", "entrypoint.bash"):
        shutil.copyfile(ROOT / "simulation_utility" / filename, simulation / filename)
    shutil.copyfile(ROOT / "Makefile", project / "Makefile")
    installation = project / "installation"
    installation.mkdir()
    (installation / "stage.bash").write_text("image installation")
    (installation / "cached_images").mkdir()
    (installation / "cached_images" / "disk.img").write_text("do not upload")
    source = tmp_path / "BLITZ"
    for filename in ("scripts/ui/install_on_system.sh", "scripts/setup.sh", "Makefile",
                     "backend/deployment/module/catalog.py"):
        path = source / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("working tree change")
    for filename in (".git/config", ".venv/private", "build/output", "backend/__pycache__/cache.pyc",
                     ".pytest_cache/state", "node_modules/module", "lib.egg-info/metadata",
                     ".env.local", "system_data/name.txt", "website/page", ".ssh/key"):
        path = source / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("excluded")
    tools = tmp_path / "bin"
    tools.mkdir()
    docker = tools / "docker"
    docker.write_text(f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
context = pathlib.Path(sys.argv[-1])
pathlib.Path(os.environ["TEST_LOG"]).write_text(json.dumps({
    "args": sys.argv[1:], "context": str(context),
    "files": {str(p.relative_to(context)): p.read_text() for p in context.rglob("*") if p.is_file()}
}))
sys.exit(int(os.environ.get("TEST_DOCKER_EXIT", "0")))
''')
    docker.chmod(0o755)
    log = tmp_path / "docker.json"
    environment = {key: value for key, value in os.environ.items()
                   if key not in ("BLITZ_SOURCE_DIR", "BLITZ_REF", "BLITZ_GIT_URL", "SIM_IMAGE")}
    environment.update(PATH=f"{tools}:{os.environ['PATH']}", TEST_LOG=str(log))
    return project, source, log, environment


def run_build(build_tree, *arguments):
    project, _, log, environment = build_tree
    result = subprocess.run(["make", "sim-build", "SIM_IMAGE=test:source", *arguments],
                            cwd=project, env=environment, capture_output=True, text=True)
    captured = json.loads(log.read_text()) if log.exists() else None
    if captured is not None:
        assert not Path(captured["context"]).exists(), "temporary context leaked"
    return result, captured


def test_default_build_includes_sibling_working_tree_and_excludes_private_files(build_tree):
    result, captured = run_build(build_tree)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "local BLITZ working tree" in result.stdout
    files = captured["files"]
    assert files["blitz-source/backend/deployment/module/catalog.py"] == "working tree change"
    assert not any(contents == "excluded" for contents in files.values())
    assert not any("cached_images" in name for name in files)
    assert files["installation/stage.bash"] == "image installation"
    assert "test:source" in captured["args"]


@pytest.mark.parametrize("arguments", [
    ("BLITZ_SOURCE_DIR=",), ("BLITZ_REF=published-v3",),
    ("BLITZ_GIT_URL=https://example.test/blitz.git",),
])
def test_explicit_git_selection_does_not_include_sibling_source(build_tree, arguments):
    result, captured = run_build(build_tree, *arguments)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Git BLITZ" in result.stdout
    assert not any(name.startswith("blitz-source/") for name in captured["files"])
    for argument in arguments:
        if not argument.startswith("BLITZ_SOURCE_DIR="):
            assert argument in captured["args"]


def test_explicit_source_path_with_spaces_wins_over_git_revision(build_tree):
    _, source, _, _ = build_tree
    selected = source.with_name("Selected source")
    source.rename(selected)
    result, captured = run_build(build_tree, f"BLITZ_SOURCE_DIR={selected}", "BLITZ_REF=old-version")
    assert result.returncode == 0, result.stdout + result.stderr
    assert str(selected) in result.stdout
    assert "blitz-source/scripts/setup.sh" in captured["files"]


def test_no_sibling_checkout_uses_git(build_tree):
    _, source, _, _ = build_tree
    shutil.rmtree(source)
    result, captured = run_build(build_tree)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Git BLITZ" in result.stdout
    assert not any(name.startswith("blitz-source/") for name in captured["files"])


def test_invalid_selected_source_fails_before_docker(build_tree):
    result, captured = run_build(build_tree, "BLITZ_SOURCE_DIR=/missing/source")
    assert result.returncode != 0
    assert "Incomplete BLITZ_SOURCE_DIR" in result.stderr
    assert captured is None


def test_failed_docker_build_propagates_failure_and_removes_context(build_tree):
    build_tree[3]["TEST_DOCKER_EXIT"] = "1"
    result, captured = run_build(build_tree)
    assert result.returncode != 0
    assert captured is not None
