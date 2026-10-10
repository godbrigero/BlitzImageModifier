#!/bin/bash

# installs distro to host machine in particular folder and returns the path to the image for caching purposes

set -euo pipefail

IMAGE_FILE=${1:?IMAGE_FILE argument required}
IMAGE_URL=${2:?IMAGE_URL argument required}


CACHE_DIR="${BLITZ_IMAGE_CACHE:-/host/installation/cached_images}"
WORKDIR_INSTALL_DIR="${BLITZ_WORKSPACE:-/workspace}"

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

if [ -f "$IMAGE_FILE.xz" ] && ! xz -t "$IMAGE_FILE.xz"; then
  echo "Cached image is incomplete/corrupt; downloading again: $IMAGE_FILE.xz" >&2
  rm -f "$IMAGE_FILE.xz"
fi
if [ ! -f "$IMAGE_FILE.xz" ]; then
  DOWNLOAD_FILE="$(mktemp "$CACHE_DIR/.download.XXXXXX")"
  trap 'rm -f "$DOWNLOAD_FILE"' EXIT
  wget -O "$DOWNLOAD_FILE" "$IMAGE_URL"
  xz -t "$DOWNLOAD_FILE"
  mv "$DOWNLOAD_FILE" "$IMAGE_FILE.xz"
fi

mkdir -p "$WORKDIR_INSTALL_DIR"
xz -d -c "$IMAGE_FILE.xz" > "$WORKDIR_INSTALL_DIR/$IMAGE_FILE"
echo "$WORKDIR_INSTALL_DIR/$IMAGE_FILE"
