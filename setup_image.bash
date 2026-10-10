#!/bin/bash
set -euo pipefail

IMAGE_FILE=$1
RUN_INSIDE_CHROOT_SCRIPT=$2

MOUNT_POINT="${BLITZ_MOUNT_POINT:-/mnt/raspios}"
WORKSPACE="${BLITZ_WORKSPACE:-/workspace}"

LOOP_DEV=""
MOUNTS=()
RESOLV_BACKUP=""

mount_image() {
    mount "$@"
    MOUNTS+=("${!#}")
}

cleanup() {
    status=$?
    set +e
    if [ -n "$RESOLV_BACKUP" ]; then
        rm -f "$MOUNT_POINT/etc/resolv.conf"
        if [ -e "$RESOLV_BACKUP/resolv.conf" ] || [ -L "$RESOLV_BACKUP/resolv.conf" ]; then
            cp -a "$RESOLV_BACKUP/resolv.conf" "$MOUNT_POINT/etc/resolv.conf"
        fi
        rm -rf "$RESOLV_BACKUP"
    fi
    if [ "$status" -ne 0 ]; then
        for ((index=${#MOUNTS[@]}-1; index>=0; index--)); do
            umount "${MOUNTS[$index]}"
        done
        if [ -n "$LOOP_DEV" ]; then
            kpartx -dv "$LOOP_DEV"
            losetup -d "$LOOP_DEV"
        fi
    fi
    exit "$status"
}
trap cleanup EXIT
if mountpoint -q "$MOUNT_POINT"; then
    echo "$MOUNT_POINT is already mounted; refusing to reuse another build's mounts" >&2
    exit 1
fi
mkdir -p "$MOUNT_POINT"
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
# e2fsck returns 1/2 when repairs succeeded; larger codes indicate failure.
fsck_status=0
e2fsck -f -y /dev/mapper/${LOOP_DEVICE}p2 || fsck_status=$?
if [ "$fsck_status" -gt 2 ]; then
    echo "Filesystem check failed (exit $fsck_status)" >&2
    exit "$fsck_status"
fi
echo "Resizing filesystem..."
resize2fs /dev/mapper/${LOOP_DEVICE}p2
echo "Partition resized successfully"

echo "Partition details:"
lsblk "$LOOP_DEV" 2>/dev/null || ls -lh /dev/mapper/
df -h | grep mapper || true
echo ""

sleep 2

mount_image /dev/mapper/${LOOP_DEVICE}p2 "$MOUNT_POINT"
BOOT_PATH="$MOUNT_POINT/boot"
if [ -d "$MOUNT_POINT/boot/firmware" ]; then
    BOOT_PATH="$MOUNT_POINT/boot/firmware"
fi
mount_image /dev/mapper/${LOOP_DEVICE}p1 "$BOOT_PATH"

cp /usr/bin/qemu-aarch64-static "$MOUNT_POINT/usr/bin/"
mount_image --bind /dev "$MOUNT_POINT/dev"
mount_image --bind /proc "$MOUNT_POINT/proc"
mount_image --bind /sys "$MOUNT_POINT/sys"
mount_image -t devpts devpts "$MOUNT_POINT/dev/pts"
mkdir -p "$MOUNT_POINT/workspace"
mount_image --bind "$WORKSPACE" "$MOUNT_POINT/workspace"
if [ -n "${BLITZ_SOURCE_DIR:-}" ]; then
    if [ ! -f "$BLITZ_SOURCE_DIR/scripts/ui/install_on_system.sh" ]; then
        echo "Local BLITZ source is not mounted correctly: $BLITZ_SOURCE_DIR" >&2
        exit 1
    fi
    mkdir -p "$MOUNT_POINT/blitz-source"
    mount_image --bind "$BLITZ_SOURCE_DIR" "$MOUNT_POINT/blitz-source"
    BLITZ_SOURCE_DIR="/blitz-source"
    export BLITZ_SOURCE_DIR
fi
# Replace dangling /etc/resolv.conf symlink (common in systemd images) with host's resolv.conf for chroot DNS
RESOLV_BACKUP="$(mktemp -d)"
if [ -e "$MOUNT_POINT/etc/resolv.conf" ] || [ -L "$MOUNT_POINT/etc/resolv.conf" ]; then
    cp -a "$MOUNT_POINT/etc/resolv.conf" "$RESOLV_BACKUP/resolv.conf"
fi
rm -f "$MOUNT_POINT/etc/resolv.conf"
cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"

echo "=== Raspberry Pi OS Ready ==="
echo "Architecture: $(chroot "$MOUNT_POINT" uname -m)"
echo "OS: $(chroot "$MOUNT_POINT" cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2)"
echo "Available disk space:"
df -h "$MOUNT_POINT" | tail -1
echo "$WORKSPACE is available inside the environment"
echo "Running interactive shell..."
echo ""

BLITZ_USER="${BLITZ_USER:-ubuntu}"
BLITZ_PASSWORD="${BLITZ_PASSWORD:-ubuntu}"
BLITZ_UID="${BLITZ_UID:-1000}"
BLITZ_GID="${BLITZ_GID:-1000}"

chroot "$MOUNT_POINT" /usr/bin/env \
    BLITZ_USER="$BLITZ_USER" \
    BLITZ_PASSWORD="$BLITZ_PASSWORD" \
    BLITZ_UID="$BLITZ_UID" \
    BLITZ_GID="$BLITZ_GID" \
    BLITZ_ROUTER_ENABLED="${BLITZ_ROUTER_ENABLED:-false}" \
    BLITZ_ROUTER_SSID="${BLITZ_ROUTER_SSID:-BLITZ}" \
    BLITZ_ROUTER_PASSWORD="${BLITZ_ROUTER_PASSWORD:-}" \
    BLITZ_ROUTER_WIFI_INTERFACE="${BLITZ_ROUTER_WIFI_INTERFACE:-wlan0}" \
    BLITZ_ROUTER_LAN_INTERFACES="${BLITZ_ROUTER_LAN_INTERFACES:-eth0}" \
    BLITZ_ROUTER_ADDRESS="${BLITZ_ROUTER_ADDRESS:-10.42.0.1/24}" \
    BLITZ_ROUTER_COUNTRY="${BLITZ_ROUTER_COUNTRY:-US}" \
    /bin/bash -lc "set -euo pipefail; cd /workspace && bash \"$RUN_INSIDE_CHROOT_SCRIPT\""
