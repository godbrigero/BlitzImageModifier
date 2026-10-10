"""Run an ephemeral C++ library/Python module through the installed watchdog."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(os.environ["BLITZ_PATH"]).resolve()
os.chdir(root)
sys.path.insert(0, str(root))

from backend.deployment.module.catalog import BackendModules
from backend.deployment.processes import WeightedProcess
from watchdog.process_starter import OpenedProcess


class Process(WeightedProcess):
    CONTROL = "smoke-control", 1.0


with tempfile.TemporaryDirectory(prefix="blitz-module-smoke-") as directory:
    bundle = Path(directory)
    source = bundle / "cpp/vision"
    source.mkdir(parents=True)
    (source / "vision.cpp").write_text('extern "C" int add(int a, int b) { return a + b; }\n')
    libraries = bundle / "lib/vision"
    libraries.mkdir(parents=True)
    subprocess.run(["c++", "-shared", "-fPIC", str(source / "vision.cpp"), "-o", str(libraries / "libvision.so")], check=True)
    program = bundle / "python/control"
    program.mkdir(parents=True)
    (program / "main.py").write_text('''import ctypes, os, sys
from pathlib import Path
assert sys.argv[1:] == []
vision = ctypes.CDLL(str(Path(os.environ["BLITZ_LIB_DIR"]) / "vision/libvision.so"))
vision.add.argtypes = [ctypes.c_int, ctypes.c_int]
vision.add.restype = ctypes.c_int
assert vision.add(20, 22) == 42
assert os.environ["BLITZ_SYSTEM_NAME"] == "smoke-target"
print("Watchdog Python module loaded compiled libvision.so: 42", flush=True)
''')
    (bundle / "runtime-manifest.json").write_text(json.dumps({"modules": {"control": {"library_paths": ["lib/vision"]}}}))
    module = BackendModules(bundle / "deploy.py").python("control", process=Process.CONTROL, entrypoint="main.py", dependencies=("vision",))
    child = OpenedProcess.start_module(module, str(bundle), {"blitz-path": str(root), "system-name": "smoke-target"})
    if child.wait(timeout=10) != 0:
        raise RuntimeError("Installed watchdog could not execute the Python/shared-library module")
