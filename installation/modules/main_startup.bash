#!/bin/bash
set -euo pipefail

cd /workspace/installation/modules/

# Provision the target image account before installing application files.
bash ./provision_user.bash

# Install system dependencies
bash ./installation_common.bash

# Install BLITZ software
bash ./installation_blitz.bash

# Install Autobahn
bash ./installation_autobahn.bash

# Install startup script
bash ./install_startup.bash

# Make the normal device user own the deployable application tree.
bash ./finalize_permissions.bash

cd /workspace
