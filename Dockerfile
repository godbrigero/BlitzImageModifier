FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    xz-utils \
    wget \
    kpartx

WORKDIR /workspace

RUN wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz && \
    xz -d 2024-07-04-raspios-bookworm-arm64-lite.img.xz

# Simple script to mount the image and drop into a shell
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Mounting Raspberry Pi OS image..."\n\
LOOP_DEVICE=$(losetup -fP --show /workspace/2024-07-04-raspios-bookworm-arm64-lite.img)\n\
mkdir -p /mnt/boot /mnt/root\n\
mount ${LOOP_DEVICE}p1 /mnt/boot\n\
mount ${LOOP_DEVICE}p2 /mnt/root\n\
echo ""\n\
echo "Image mounted!"\n\
echo "  Boot partition: /mnt/boot"\n\
echo "  Root partition: /mnt/root"\n\
echo ""\n\
echo "Make your modifications, then exit to unmount."\n\
/bin/bash\n\
echo "Unmounting..."\n\
umount /mnt/boot /mnt/root\n\
losetup -d ${LOOP_DEVICE}\n\
echo "Done!"\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]