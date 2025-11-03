#!/bin/bash

sudo apt-get update
sudo apt install -y \
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
    python3-opencv \
    python3-pip \
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
    liblzma-dev

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

mkdir -p ~/Documents