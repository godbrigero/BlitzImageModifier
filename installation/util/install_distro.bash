#!/bin/bash

# installs distro to host machine in particular folder and returns the path to the image for caching purposes

set -euo pipefail

IMAGE_FILE=${1:?IMAGE_FILE argument required}
IMAGE_URL=${2:?IMAGE_URL argument required}


CACHE_DIR="/host/installation/cached_images"
WORKDIR_INSTALL_DIR="/workspace"

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

if [ ! -f "$IMAGE_FILE.xz" ]; then
  wget -O "$IMAGE_FILE.xz" "$IMAGE_URL"
fi

xz -d -c "$IMAGE_FILE.xz" > "$WORKDIR_INSTALL_DIR/$IMAGE_FILE"
echo "$WORKDIR_INSTALL_DIR/$IMAGE_FILE"