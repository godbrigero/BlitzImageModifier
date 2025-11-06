FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    xz-utils \
    wget \
    kpartx \
    qemu-user-static \
    binfmt-support \
    systemd-container \
    parted

WORKDIR /workspace

RUN wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz && \
    xz -d 2024-07-04-raspios-bookworm-arm64-lite.img.xz && \
    echo "Image downloaded and extracted"

RUN mkdir -p /mnt/raspios

COPY . /workspace

CMD echo "Setting up Raspberry Pi OS environment..." && \
    LOOP_DEVICE=$(kpartx -av 2024-07-04-raspios-bookworm-arm64-lite.img | head -1 | awk '{print $3}' | sed 's/p1$//') && \
    echo "Using loop device: ${LOOP_DEVICE}" && \
    ls -la /dev/mapper/ && \
    mount /dev/mapper/${LOOP_DEVICE}p2 /mnt/raspios && \
    mount /dev/mapper/${LOOP_DEVICE}p1 /mnt/raspios/boot && \
    cp /usr/bin/qemu-aarch64-static /mnt/raspios/usr/bin/ && \
    mount --bind /dev /mnt/raspios/dev && \
    mount --bind /proc /mnt/raspios/proc && \
    mount --bind /sys /mnt/raspios/sys && \
    mount -t devpts devpts /mnt/raspios/dev/pts && \
    mkdir -p /mnt/raspios/workspace && \
    mount --bind /workspace /mnt/raspios/workspace && \
    cp /etc/resolv.conf /mnt/raspios/etc/resolv.conf && \
    echo "" && \
    echo "=== Raspberry Pi OS Ready ===" && \
    echo "Architecture: $(chroot /mnt/raspios uname -m)" && \
    echo "OS: $(chroot /mnt/raspios cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)" && \
    echo "/workspace is available inside the environment" && \
    echo "Running interactive shell..." && \
    echo "" && \
    chroot /mnt/raspios /bin/bash -lc 'cd /workspace && bash ./main_startup.sh pi5.sh'
