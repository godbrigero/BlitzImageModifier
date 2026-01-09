#!/bin/bash
set -euo pipefail

# install common packages for ALL devices

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    cmake \
    protobuf-compiler \
    thrift-compiler \
    make \
    pkg-config \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip \
    python3-opencv \
    libssl-dev \
    libclang-dev \
    sshpass \
    rsync \
    udev \
    avahi-daemon \
    avahi-utils \
    libnss-mdns \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    liblzma-dev \
    openssh-server

sudo systemctl enable ssh
# sudo systemctl start ssh
# sudo systemctl status ssh

sudo systemctl enable avahi-daemon
# sudo systemctl start avahi-daemon

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
. $HOME/.cargo/env

PYTHON3_PATH="$(command -v python3)"
if [ -z "$PYTHON3_PATH" ]; then
  echo "python3 is not installed; aborting." >&2
  exit 1
fi

sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python

python3 --version
python --version

mkdir -p /opt/blitz