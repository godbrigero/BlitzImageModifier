#!/bin/bash
set -euo pipefail

# /workspace is shared across image builds; preserve the source script.
sudo install -m 0755 /workspace/installation/system-patch/blitzprojstartup.bash /usr/local/bin/blitzprojstartup.bash
line="sudo /usr/local/bin/blitzprojstartup.bash"
grep -qxF "$line" /etc/bash.bashrc || printf '%s\n' "$line" >> /etc/bash.bashrc
