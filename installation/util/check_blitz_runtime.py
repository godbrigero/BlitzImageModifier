"""Check the installed target runtime without Docker or network access."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import shutil


def check_runtime(root: Path) -> str:
    os.chdir(root)
    sys.path.insert(0, str(root))
    from backend.deployment.module.catalog import BackendModules
    from backend.deployment.module.contracts import LaunchSettings
    from backend.deployment.module.supported import SupportedModules
    from backend.deployment.processes import ProcessPlan
    from watchdog.process_starter import OpenedProcess
    from watchdog.util.system import DiscoveredNetworkSystem

    version = (root / "backend/deployment/.blitz-build-version").read_text().strip()
    try:
        parts = tuple(int(part) for part in version.split("."))
    except ValueError as error:
        raise RuntimeError(f"Invalid BLITZ deployment version: {version}") from error
    if parts < (1, 2, 0):
        raise RuntimeError(f"BLITZ deployment {version} is too old; require 1.2.0 or later")
    if LaunchSettings().accepts_blitz_flags:
        raise RuntimeError("Runtime unexpectedly injects legacy BLITZ CLI flags")
    modules = BackendModules(root / "backend/deploy.py")
    if Path(modules.backend_path) != root / "backend":
        raise RuntimeError("Backend module root does not match the installed source tree")
    # Discovery uses the same target-side collector as the mDNS bridge and API.
    discovered = DiscoveredNetworkSystem.collect()
    if Path(discovered.blitz_path).resolve() != root:
        raise RuntimeError("Watchdog discovery advertises a different installation root")
    for name in ("rsync", "unzip", "ssh"):
        if shutil.which(name) is None:
            raise RuntimeError(f"Missing offline deployment tool: {name}")
    return version


if __name__ == "__main__":
    root = Path(os.environ.get("BLITZ_PATH", "/opt/blitz/B.L.I.T.Z")).resolve()
    version = check_runtime(root)
    print(f"BLITZ deployment {version}: module APIs, watchdog discovery, and offline tools verified")
