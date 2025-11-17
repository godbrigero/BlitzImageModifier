#!/bin/bash
ARGS=$1

set -euo pipefail

IMAGE_FILE="2024-07-04-raspios-bookworm-arm64-lite.img"
MOUNT_POINT="/mnt/raspios"
WORKSPACE="/workspace"

echo "Unmounting everything that setup_image.sh mounted..."

LOOP_DEV=$(losetup -j "$IMAGE_FILE" | cut -d: -f1)
if [ -z "$LOOP_DEV" ]; then
  echo "❌ No loop device found for $IMAGE_FILE"
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
ls -lh "$IMAGE_FILE"

echo "Done with image! Exporting and compressing..."
mv "$IMAGE_FILE" "${ARGS}.img"

mkdir -p /host/outputs/
cp "${ARGS}.img" /host/outputs/${ARGS}.img