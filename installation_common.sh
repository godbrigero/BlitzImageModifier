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

if ! command -v rustc >/dev/null 2>&1; then
  echo "Rust is not installed. Installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "Rust is already installed."
fi

rustc --version || echo "Rust installation failed or path not set."

PYTHON3_PATH="$(command -v python3)"
if [ -z "$PYTHON3_PATH" ]; then
  echo "python3 is not installed; aborting." >&2
  exit 1
fi

sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python

python3 --version
python --version

mkdir -p ~/Documents