#!/bin/bash
set -euo pipefail

cd /workspace/installation/modules/

# Install system dependencies
bash ./installation_common.bash

# Install BLITZ software
bash ./installation_blitz.bash

# Install Autobahn
bash ./installation_autobahn.bash

cd /workspace