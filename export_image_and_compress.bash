#!/bin/bash
set -euo pipefail

INPUT_IMAGE=${1:?INPUT_IMAGE argument required (path to .img)}
OUTPUT_BASENAME=${2:?OUTPUT_BASENAME argument required (e.g. pi5_flash_image)}
DO_COMPRESSION=${3:-true}

MOUNT_POINT="/mnt/raspios"

echo "Unmounting everything that setup_image.bash mounted..."

LOOP_DEV=$(losetup -j "$INPUT_IMAGE" | cut -d: -f1)
if [ -z "$LOOP_DEV" ]; then
  echo "❌ No loop device found for $INPUT_IMAGE"
  exit 1
fi

LOOP_DEVICE=$(basename "$LOOP_DEV")

umount -lf "$MOUNT_POINT/dev/pts" || true
umount -lf "$MOUNT_POINT/dev" || true
umount -lf "$MOUNT_POINT/proc" || true
umount -lf "$MOUNT_POINT/sys" || true
umount -lf "$MOUNT_POINT/workspace" || true
umount -lf "$MOUNT_POINT/boot" || true
umount -lf "$MOUNT_POINT" || true

kpartx -dv "$LOOP_DEV" || true
sync
losetup -d "$LOOP_DEV" || true

echo "Image size:"
ls -lh "$INPUT_IMAGE"

mkdir -p /host/outputs/
echo "Done with image! Exporting..."
cp "$INPUT_IMAGE" "/host/outputs/${OUTPUT_BASENAME}.img"

if [ "$DO_COMPRESSION" = true ]; then
  echo "Compressing image..."
  xz -T 0 -v "/host/outputs/${OUTPUT_BASENAME}.img"
  echo "Image compressed successfully"
else
  echo "Skipping compression"
fi