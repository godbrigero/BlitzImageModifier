## BlitzImageModifier

#### Disclaimer: README is written by AI and reviewed by me.

Create a preconfigured Raspberry Pi OS image (Pi 5, Bookworm arm64) with the Pinewood Robotics B.L.I.T.Z stack and Autobahn preinstalled. The build runs entirely inside Docker using QEMU, expands the base image, chroots into it to install packages and services, and then exports a compressed `.img.xz` ready to flash.

### What this does

- **Downloads** Raspberry Pi OS Lite (arm64 Bookworm) base image
- **Expands** the image filesystem to add space (+4 GB by default)
- **Chroots** into the image using QEMU to install software
- **Installs** common system deps, Rust toolchain, SSH, mDNS
- **Installs** B.L.I.T.Z (branch `merge-backend`) and Autobahn
- **Applies** USB udev naming rules and enables required services
- **Configures** a first-boot service that asks for a device name
- **Exports** and **compresses** the final image to `outputs/`

## Prerequisites

- Docker Engine (or Docker Desktop) and Docker Compose
- Host OS: Linux recommended; macOS with Docker Desktop also works (runs in a Linux VM under the hood). Windows WSL2 with Docker may work as well.
- Sufficient disk space (downloaded image + expanded working set; plan for ~10–15 GB)
- Internet access (clones/installs inside the chroot)

## Quick start

```bash
git clone https://github.com/your-org/BlitzImageModifier.git
cd BlitzImageModifier

# Build and run the image creation pipeline
docker compose up --build
```

When the pipeline finishes, your output will be in:

```bash
outputs/pi5_flash_image.img.xz
```

You can then flash it to a microSD card (Linux example):

```bash
xz -d outputs/pi5_flash_image.img.xz

# Replace /dev/sdX with your target device (DANGER: double-check!)
sudo dd if=outputs/pi5_flash_image.img of=/dev/sdX bs=4M status=progress conv=fsync
```

## How it works (high level)

- `Dockerfile`

  - Based on `ubuntu:24.04`, installs tooling (qemu-user-static, kpartx, parted, e2fsprogs, etc.)
  - Downloads `raspios-bookworm-arm64-lite` and expands the image by 4 GB
  - Entrypoint runs `setup_image.bash` then `export_image_and_compress.bash`

- `setup_image.bash`

  - Attaches loop devices, fixes/extends partitions, runs `resize2fs`
  - Mounts the image (root and boot), binds `/dev`, `/proc`, `/sys`, `/workspace`
  - Copies `qemu-aarch64-static` into the chroot for ARM emulation
  - Chroots into the image and runs `main_startup.bash pi5.bash`

- Inside the chroot (`main_startup.bash`)

  - Runs hardware script `pi5.bash` (installs udev rule)
  - Runs `installation_common.bash` (packages, Rust, SSH/mDNS enable)
  - Runs `installation_blitz.bash` (clones B.L.I.T.Z, `scripts/install.bash` with default name)
  - Runs `installation_autobahn.bash` (clones Autobahn, installs)
  - Runs `post_install.bash` (installs and enables first-boot service)

- `export_image_and_compress.bash`
  - Cleanly unmounts/breaks down loop/mapper devices
  - Renames the image, compresses to `.img.xz`, and copies into `./outputs/`

## First boot behavior

- A systemd service (`blitz_project.service`) runs `/usr/local/bin/blitzprojstartup.bash`.
- On first boot, if the default name is still set, it will prompt on the console for a new device name and apply it (`hostnamectl`, `/etc/hosts`, restart Avahi/SSH), then reboot.
  - If you need a non-interactive first boot, pre-create `name.txt` inside the image at:
    - `/opt/blitz/B.L.I.T.Z/system_data/name.txt`

## Customization

- **Base image version**: in `Dockerfile` (`wget` URL). Update to a newer Raspberry Pi OS image if desired.
- **Extra space**: in `Dockerfile` (`truncate -s +4G ...`). Increase if you need more room preinstalled.
- **Hardware script**: currently `main_startup.bash` runs `pi5.bash`. Add your own script and change the argument in `setup_image.bash` (`main_startup.bash <your-script>.bash`).
- **B.L.I.T.Z branch**: in `installation_blitz.bash` (`BRANCH_NAME="merge-backend"`). Change as needed.
- **Default device name**: `installation_blitz.bash` (`DEFAULT_PI_NAME`). This is used on first boot before prompting.
- **udev rules**: edit `installation/system-patch/90-usb-port-names.rules` or adapt `pi5.bash` to your hardware.
- **Output filename**: `export_image_and_compress.bash` is invoked with `pi5_flash_image` by default (from `Dockerfile CMD`). Change it if you want a different name.

## Directory overview

- `Dockerfile`: Builder and orchestrator for the image creation
- `compose.yml`: Docker Compose service (privileged) that runs the pipeline
- `setup_image.bash`: Mounts/extends the downloaded image and enters chroot
- `main_startup.bash`: Orchestrates installs and setup inside the chroot
- `pi5.bash`: Installs udev rule for USB port naming
- `installation_common.bash`: Common packages, Rust toolchain, SSH/mDNS enable
- `installation_blitz.bash`: Clones/installs B.L.I.T.Z
- `installation_autobahn.bash`: Clones/installs Autobahn
- `post_install.bash`: Installs and enables first-boot naming service
- `blitz_project.service`: systemd unit for first-boot naming
- `blitzprojstartup.bash`: prompts for device name on first boot
- `export_image_and_compress.bash`: unmounts, compresses, and copies output
- `outputs/`: final `.img.xz` artifacts

## Troubleshooting

- The build needs a privileged container for loop/mapper devices. Ensure Compose runs with `privileged: true` (already in `compose.yml`).
- On macOS/Windows, Docker runs inside a Linux VM; the pipeline runs in that VM and should still work, but performance can be slower.
- If the build fails while chrooting, verify that `qemu-user-static` was copied and `binfmt` is active (handled by the Dockerfile).
- If the output file is missing, check container logs for unmount/cleanup issues near the end.
- If first-boot name prompt is undesirable (e.g., headless), pre-seed `name.txt` as noted above.

## Common commands

```bash
# Build and run
docker compose up --build

# Clean Compose state (if you re-run)
docker compose down -v

# Remove old outputs (optional)
rm -f outputs/*.img outputs/*.img.xz
```

## Notes

- Port `5555` is exposed in `compose.yml` for possible stack services; adjust as needed.
- SSH and Avahi (mDNS) are enabled in the image so it is discoverable on the network as soon as it boots.

## License

Add a license here (e.g., MIT, Apache-2.0) if applicable.
