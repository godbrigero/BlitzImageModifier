#!/bin/bash
set -euo pipefail

BUILD_ALL=${1:-false}
BUILD_SPECIFIC=${2:-}
COMPRESS_OUTPUT=${3:-false}
EXPAND_IMAGE_SIZE=${4:-6G}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -a
source "$SCRIPT_DIR/devices.conf"
set +a

function build() {
    local SCRIPT_PATH=$1
    local SCRIPT_NAME
    SCRIPT_NAME=$(basename "$SCRIPT_PATH")
    local SCRIPT_KEY
    SCRIPT_KEY=$(echo "${SCRIPT_NAME%.*}" | tr '[:lower:]' '[:upper:]')

    local IMAGE_FILE
    local IMAGE_URL
    local IMAGE_FILE_NAME="${SCRIPT_KEY}_IMAGE_FILE"
    local IMAGE_URL_NAME="${SCRIPT_KEY}_IMAGE_URL"
    IMAGE_FILE="${!IMAGE_FILE_NAME:-}"
    IMAGE_URL="${!IMAGE_URL_NAME:-}"
    if [ -z "$IMAGE_FILE" ] || [ -z "$IMAGE_URL" ]; then
        echo "Missing image config for $SCRIPT_NAME. Expected $IMAGE_FILE_NAME and $IMAGE_URL_NAME in devices.conf" >&2
        exit 1
    fi

    cd /workspace
    local UNZIPPED_IMAGE_PATH
    UNZIPPED_IMAGE_PATH=$(bash ./installation/util/install_distro.bash "$IMAGE_FILE" "$IMAGE_URL")
    echo "UNZIPPED_IMAGE_PATH: $UNZIPPED_IMAGE_PATH"
    truncate -s +$EXPAND_IMAGE_SIZE "$UNZIPPED_IMAGE_PATH"
    
    # Run the per-device script inside the chroot. Path must be valid inside the container/chroot.
    local SCRIPT_IN_CHROOT="./installation/devices_and_distros/$SCRIPT_NAME"
    bash ./setup_image.bash "$UNZIPPED_IMAGE_PATH" "$SCRIPT_IN_CHROOT"

    bash ./export_image_and_compress.bash "$UNZIPPED_IMAGE_PATH" "${SCRIPT_NAME%.*}_flash_image" "$COMPRESS_OUTPUT"
}

if [ "$BUILD_ALL" = true ]; then
    # Run all scripts in the directory
    cd "$SCRIPT_DIR"
    for file in *.bash; do
        [[ "$file" == "build.bash" || "$file" == "devices.conf" ]] && continue
        [[ ! -e "$file" ]] && continue
        build "$file"
    done
else
    # Run only the specific build script (e.g. pi5)
    if [ -z "$BUILD_SPECIFIC" ]; then
        echo "BUILD_SPECIFIC is required when BUILD_ALL=false (e.g. pi5)" >&2
        exit 1
    fi
    cd "$SCRIPT_DIR"
    build "${BUILD_SPECIFIC}.bash"
fi