#!/bin/bash
set -euo pipefail

BLITZ_DEVICE=pi5 BLITZ_IMAGE_BUILD=true BLITZ_PYTHON_SYSTEM_PACKAGES=true \
bash /workspace/installation/modules/main_startup.bash
