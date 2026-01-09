#!/bin/bash
set -euo pipefail

IMAGE_FILE=$1
RUN_INSIDE_CHROOT_SCRIPT=$2

MOUNT_POINT="/mnt/raspios"
WORKSPACE="/workspace"

echo "Setting up Raspberry Pi OS environment..."

LOOP_DEV=$(losetup -fP --show "$IMAGE_FILE")
echo "Using loop device: $LOOP_DEV"

echo "Fixing partition table to recognize expanded image..."
sgdisk -e "$LOOP_DEV" 2>/dev/null || echo "Not a GPT disk or already fixed"

echo "Fix" | parted ---pretend-input-tty "$LOOP_DEV" print 2>&1 > /dev/null || true

echo "Resizing partition to use available space..."
parted -s "$LOOP_DEV" resizepart 2 100%

LOOP_DEVICE=$(echo $LOOP_DEV | sed 's|/dev/||')
kpartx -av "$LOOP_DEV"

echo "Checking filesystem..."
e2fsck -f -y /dev/mapper/${LOOP_DEVICE}p2
echo "Resizing filesystem..."
resize2fs /dev/mapper/${LOOP_DEVICE}p2
echo "Partition resized successfully"

echo "Partition details:"
lsblk "$LOOP_DEV" 2>/dev/null || ls -lh /dev/mapper/
df -h | grep mapper || true
echo ""

sleep 2

mount /dev/mapper/${LOOP_DEVICE}p2 "$MOUNT_POINT"
mount /dev/mapper/${LOOP_DEVICE}p1 "$MOUNT_POINT/boot"

cp /usr/bin/qemu-aarch64-static "$MOUNT_POINT/usr/bin/"
mount --bind /dev "$MOUNT_POINT/dev"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys "$MOUNT_POINT/sys"
mount -t devpts devpts "$MOUNT_POINT/dev/pts"
mkdir -p "$MOUNT_POINT/workspace"
mount --bind "$WORKSPACE" "$MOUNT_POINT/workspace"
cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

echo "=== Raspberry Pi OS Ready ==="
echo "Architecture: $(chroot "$MOUNT_POINT" uname -m)"
echo "OS: $(chroot "$MOUNT_POINT" cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2)"
echo "Available disk space:"
df -h "$MOUNT_POINT" | tail -1
echo "$WORKSPACE is available inside the environment"
echo "Running interactive shell..."
echo ""

chroot "$MOUNT_POINT" /bin/bash -lc "set -euo pipefail; cd /workspace && bash \"$RUN_INSIDE_CHROOT_SCRIPT\""