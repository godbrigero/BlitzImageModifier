#!/bin/bash
set -euo pipefail

INPUT_IMAGE=${1:?INPUT_IMAGE argument required (path to .img)}
OUTPUT_BASENAME=${2:?OUTPUT_BASENAME argument required (e.g. pi5_flash_image)}
DO_COMPRESSION=${3:-true}

MOUNT_POINT="${BLITZ_MOUNT_POINT:-/mnt/raspios}"
OUTPUT_DIR="${BLITZ_OUTPUT_DIR:-/host/outputs}"

echo "Unmounting everything that setup_image.bash mounted..."

LOOP_DEV=$(losetup -j "$INPUT_IMAGE" | cut -d: -f1)
if [ -z "$LOOP_DEV" ]; then
  echo "❌ No loop device found for $INPUT_IMAGE"
  exit 1
fi

LOOP_DEVICE=$(basename "$LOOP_DEV")

sync
for path in dev/pts dev proc sys blitz-source workspace boot/firmware boot .; do
    if mountpoint -q "$MOUNT_POINT/$path"; then
        # A busy filesystem must fail export rather than copy a still-live image.
        umount "$MOUNT_POINT/$path"
    fi
done

kpartx -dv "$LOOP_DEV"
sync
losetup -d "$LOOP_DEV"

echo "Image size:"
ls -lh "$INPUT_IMAGE"

mkdir -p "$OUTPUT_DIR"
echo "Done with image! Exporting..."
EXPORT_FILE="$(mktemp "$OUTPUT_DIR/.export.XXXXXX")"
trap 'rm -f "$EXPORT_FILE"' EXIT
cp "$INPUT_IMAGE" "$EXPORT_FILE"
chmod --reference="$INPUT_IMAGE" "$EXPORT_FILE"
mv "$EXPORT_FILE" "$OUTPUT_DIR/${OUTPUT_BASENAME}.img"

if [ "$DO_COMPRESSION" = true ]; then
  echo "Compressing image..."
  xz -T 0 -v -f "$OUTPUT_DIR/${OUTPUT_BASENAME}.img"
  echo "Image compressed successfully"
else
  echo "Skipping compression"
fi
