#!/bin/bash
set -euo pipefail

# install common packages for ALL devices
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
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
    udev \
    avahi-daemon \
    avahi-utils \
    libnss-mdns \
    openssh-server \
    python3-dev \
    nano

curl -fsSL https://pyenv.run | bash
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
pyenv install 3.12.6
pyenv global 3.12.6

pip install opencv-python

sudo systemctl enable ssh
# sudo systemctl start ssh
# sudo systemctl status ssh

sudo systemctl enable avahi-daemon
# sudo systemctl start avahi-daemon

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
. $HOME/.cargo/env

PYTHON3_PATH="$(command -v python3.12)"
if [ -z "$PYTHON3_PATH" ]; then
  echo "python3.12 is not installed; aborting." >&2
  exit 1
fi

sudo ln -sf "$PYTHON3_PATH" /usr/local/bin/python

python3 --version
python --version