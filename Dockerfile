FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    xz-utils \
    wget \
    kpartx \
    qemu-user-static \
    binfmt-support \
    systemd-container \
    parted \
    e2fsprogs \
    gdisk

WORKDIR /workspace

RUN wget https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz && \
    xz -d 2024-07-04-raspios-bookworm-arm64-lite.img.xz && \
    echo "Image downloaded and extracted" && \
    truncate -s +6G 2024-07-04-raspios-bookworm-arm64-lite.img && \
    echo "Image expanded by 6GB"

RUN mkdir -p /mnt/raspios

COPY . /workspace

CMD bash ./setup_image.sh && bash ./export_image_and_compress.sh pi5_flash_image