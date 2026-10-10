#!/bin/bash
set -euo pipefail

SUDO=()
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    SUDO=(sudo)
fi

# install common packages for ALL devices
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sudo \
    curl \
    git \
    build-essential \
    make \
    cmake \
    protobuf-compiler \
    thrift-compiler \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    liblzma-dev \
    xz-utils \
    libncursesw5-dev \
    tk-dev \
    uuid-dev \
    libgdbm-dev \
    libnss3-dev \
    libclang-dev \
    sshpass \
    rsync \
    unzip \
    udev \
    systemd \
    iproute2 \
    avahi-daemon \
    avahi-utils \
    libnss-mdns \
    openssh-server \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    nano

# Pi hardware bindings must use distro Python. Older Jetson distros need a
# newer interpreter for the current BLITZ package dependencies.
PYTHON_MODE="${BLITZ_PYTHON_MODE:-auto}"
if [ "${BLITZ_DEVICE:-}" = pi5 ]; then
    PYTHON_MODE=system
elif [ "$PYTHON_MODE" = auto ]; then
    if /usr/bin/python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
        PYTHON_MODE=system
    else
        PYTHON_MODE=managed
    fi
fi
case "$PYTHON_MODE" in
    system) echo "Using distribution Python for BLITZ" ;;
    managed)
        if [ ! -x "$HOME/.pyenv/bin/pyenv" ]; then
            curl -fsSL https://pyenv.run | bash
        fi
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        pyenv install --skip-existing "${BLITZ_PYTHON_VERSION:-3.12.6}"
        ;;
    *) echo "Invalid BLITZ_PYTHON_MODE: $PYTHON_MODE (use auto, system, or managed)" >&2; exit 1 ;;
esac

# OpenCV and other application libraries belong in the project's requirements.
# Do not install them into an unrelated global/pyenv environment here.

if [ ! -x "$HOME/.cargo/bin/rustc" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
. "$HOME/.cargo/env"

"${SUDO[@]}" systemctl enable ssh

"${SUDO[@]}" systemctl enable avahi-daemon
# Enable units for first boot; a chroot has no running systemd manager.
if systemctl is-system-running >/dev/null 2>&1 || \
    [ "$(systemctl is-system-running 2>/dev/null || true)" = degraded ]; then
    "${SUDO[@]}" systemctl start ssh avahi-daemon
fi
