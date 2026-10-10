#!/bin/bash
set -euo pipefail

ROOT="${BLITZ_INSTALLATION_DIR:-/opt/blitz}/B.L.I.T.Z"
# BLITZ's Autobahn client requires NumPy 2. Bookworm's apt simplejpeg uses the
# NumPy 1 ABI. This upstream wheel supports the shared environment's NumPy ABI.
# Install once during online image provisioning, not during offline deployment.
"$ROOT/.venv/bin/python" -m pip install --index-url https://pypi.org/simple \
    --only-binary=:all: --no-deps --upgrade simplejpeg==1.9.0
