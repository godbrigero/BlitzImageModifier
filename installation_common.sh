#!/bin/bash

PYTHON_VERSION="3.12.6"

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

curl https://pyenv.run | bash

export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

if ! grep -q 'pyenv init' ~/.bashrc; then
cat << 'EOF' >> ~/.bashrc

# Pyenv configuration
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
fi

pyenv install -s $PYTHON_VERSION
pyenv global $PYTHON_VERSION

python --version

mkdir ~/Documents