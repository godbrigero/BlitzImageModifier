"""Check the installed target runtime without Docker or network access."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import shutil
import platform


def check_runtime(root: Path) -> str:
    os.chdir(root)
    sys.path.insert(0, str(root))
    from backend.deployment.module.catalog import BackendModules
    from backend.deployment.module.contracts import LaunchSettings
    from backend.deployment.module.supported import SupportedModules
    from backend.deployment.processes import ProcessPlan
    from watchdog.process_starter import OpenedProcess
    from watchdog.util.system import collect_system_catalog

    version = (root / "backend/deployment/.blitz-build-version").read_text().strip()
    try:
        parts = tuple(int(part) for part in version.split("."))
    except ValueError as error:
        raise RuntimeError(f"Invalid BLITZ deployment version: {version}") from error
    if parts < (3, 0, 0):
        raise RuntimeError(f"BLITZ deployment {version} is too old; require 3.0.0 or later")
    if LaunchSettings().accepts_blitz_flags:
        raise RuntimeError("Runtime unexpectedly injects legacy BLITZ CLI flags")
    modules = BackendModules(root / "backend/deploy.py")
    if Path(modules.backend_path) != root / "backend":
        raise RuntimeError("Backend module root does not match the installed source tree")
    # The watchdog caches HTTP catalogs built by this target-side collector.
    discovered = collect_system_catalog()
    if Path(discovered.blitz_path).resolve() != root:
        raise RuntimeError("Watchdog discovery advertises a different installation root")
    tools = ("rsync", "unzip", "ssh", "ip") if platform.system() == "Linux" else ("rsync", "unzip", "ssh")
    for name in tools:
        if shutil.which(name) is None:
            raise RuntimeError(f"Missing offline deployment tool: {name}")
    return version


if __name__ == "__main__":
    root = Path(os.environ.get("BLITZ_PATH", "/opt/blitz/B.L.I.T.Z")).resolve()
    version = check_runtime(root)
    print(f"BLITZ deployment {version}: module APIs, watchdog discovery, and offline tools verified")
