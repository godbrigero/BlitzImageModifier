#!/bin/bash
set -euo pipefail

cd /workspace/installation/modules/

# Provision the target image account before installing application files.
bash ./provision_user.bash

# Install system dependencies
bash ./installation_common.bash

if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    bash ./installation_pi5_hardware.bash
fi

# Install BLITZ software
bash ./installation_blitz.bash
if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    bash ./installation_pi5_python.bash
fi

# Install Autobahn
bash ./installation_autobahn.bash

# Install startup script
bash ./install_startup.bash

# Make the normal device user own the deployable application tree.
bash ./finalize_permissions.bash

# Check everything needed at first boot, not only the deployment API imports.
bash ./validate_image.bash

cd /workspace
