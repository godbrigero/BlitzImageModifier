"""Verify that the installed live service advertises this checkout and identity."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen


def wait_for_catalog(root: Path, port: int, system_name: str, timeout: float = 30) -> None:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while True:
        try:
            # Profile collection may spend up to three seconds probing NVIDIA.
            with urlopen(f"http://127.0.0.1:{port}/get/system/catalog", timeout=5) as response:
                identity = json.load(response)
            from backend.deployment.network_api.catalog import SystemCatalog

            identity = SystemCatalog.from_payload(identity).to_dict()
            if Path(identity["blitz_path"]).resolve() != root.resolve():
                raise RuntimeError("Watchdog HTTP API advertises a different installation root")
            if identity["system_name"] != system_name:
                raise RuntimeError("Watchdog HTTP API advertises a different device name")
            print("Live watchdog HTTP identity verified")
            return
        except (URLError, TimeoutError, ValueError, KeyError) as error:
            last_error = error
        if time.monotonic() >= deadline:
            raise RuntimeError("Watchdog HTTP API did not become ready: {}".format(last_error))
        time.sleep(1)


if __name__ == "__main__":
    root = Path(os.environ["BLITZ_PATH"]).resolve()
    os.chdir(root)
    sys.path.insert(0, str(root))
    from watchdog.util.system import get_system_name, load_basic_system_config

    wait_for_catalog(root, load_basic_system_config().watchdog_api.api_port, get_system_name())
