# How This Project Works and How to Customize It

This project builds a Raspberry Pi OS image that already has the Pinewood Robotics software stack installed (B.L.I.T.Z + Autobahn), plus some device-specific system setup.

The important idea is: **do all the image editing inside Docker**, using QEMU so we can chroot into an ARM64 Raspberry Pi OS image from an x86_64 machine.

## What this project produces

- A flashable Raspberry Pi OS `.img` file (optionally compressed to `.img.xz`)
- The image is preconfigured so the device boots with:
  - system dependencies installed
  - SSH + mDNS enabled (so it is reachable on the network)
  - B.L.I.T.Z installed (from a chosen branch)
  - Autobahn installed
  - a USB udev naming rule applied (so ports map to stable names)
  - a first-boot flow that asks you to set the device name (hostname)

Outputs are written to `outputs/`.

## Big picture flow (methodology)

The pipeline is a sequence of small steps. Each step has one job and is easy to swap out.

### 1) Build container environment

- `Dockerfile` installs the tools needed to manipulate disk images:
  - loop devices, partition tools, filesystem tools
  - `qemu-user-static` so the host can execute ARM64 binaries via emulation
- `compose.yml` runs the container in **privileged** mode so loop devices and `kpartx` work.

### 2) Pick a target device and base OS image

- Device definitions live in `installation/devices_and_distros/`.
- `devices.conf` maps device keys to a Raspberry Pi OS download URL and filename.
- The entrypoint (`installation/devices_and_distros/build.bash`) chooses:
  - build all device scripts, or
  - build one device script (example: `pi5`)

### 3) Download and unpack the base image (with caching)

- `installation/util/install_distro.bash` downloads the `.img.xz` into:
  - `installation/cached_images/` (on the host via the Docker volume)
- It then decompresses into the container workspace so we can edit it.

Why this is structured this way:

- **Host cache** avoids re-downloading the large base image every run.
- **Workspace copy** avoids mutating the cached file and keeps each run reproducible.

### 4) Expand partitions and mount the image

- `installation/devices_and_distros/build.bash` expands the image file size using `truncate`.
- `setup_image.bash` does the low-level disk work:
  - attaches the image to a loop device
  - repairs/rescans the partition table (handles “expanded image” correctly)
  - resizes partition 2 to fill the available space
  - runs `e2fsck` and `resize2fs`
  - mounts root and boot partitions under `/mnt/raspios`
  - bind-mounts `/dev`, `/proc`, `/sys`, and the repo workspace into the chroot
  - copies `qemu-aarch64-static` into the image so `chroot` can run ARM64 binaries

This step is separated because it is “image plumbing” and is the same no matter which device or software stack you install.

### 5) Chroot into the image and install everything

Once mounted, `setup_image.bash` runs a device script inside the image:

- The device script (example: `installation/devices_and_distros/pi5.bash`) runs:
  - `installation/modules/main_startup.bash` to install the software stacks
  - device-specific patches (example: install a udev rules file)

Inside `installation/modules/main_startup.bash` the work is split into modules:

- `installation_common.bash`
  - installs OS packages and tools (git, python, build tools, OpenCV, etc.)
  - enables services like SSH and Avahi
  - installs Rust (via rustup) and ensures `python` points to `python3`
  - prepares `/opt/blitz`
- `installation_blitz.bash`
  - clones `B.L.I.T.Z` into `/opt/blitz/B.L.I.T.Z`
  - checks out a specific branch (`merge-backend` in the current script)
  - runs the project installer with a default name
- `installation_autobahn.bash`
  - clones Autobahn into `/opt/blitz/autobahn`
  - runs its installer script

Why the modules folder exists:

- **Common setup** is shared across devices.
- **Per-project installs** are separate so you can add/remove components cleanly.
- **Per-device scripts** stay small and focus on hardware/OS tweaks.

### 6) Apply device-specific system patches

For Pi 5, `installation/devices_and_distros/pi5.bash` installs:

- `installation/system-patch/90-usb-port-names.rules` into `/etc/udev/rules.d/`

This creates stable symlinks like `usb_cam1`, `usb_cam2`, etc., based on physical USB port topology.

Keeping this in `installation/system-patch/` makes it obvious that this is “OS configuration”, not “application code”.

### 7) Export (and optionally compress) the final image

- `export_image_and_compress.bash`:
  - unmounts everything mounted by `setup_image.bash`
  - detaches `kpartx` mappings and loop devices
  - copies the final `.img` into `/host/outputs/` (mapped to repo `outputs/`)
  - optionally compresses it using `xz`

This is separated so cleanup and export logic is consistent and easy to debug.

## First boot naming behavior (hostname)

The system is intended to ship with a placeholder name first, then ask for a real name on first boot.

- `installation/system-patch/blitzprojstartup.bash` checks this file:
  - `/opt/blitz/B.L.I.T.Z/system_data/name.txt`
- If it is missing, it creates it with the default placeholder name.
- If it still equals the placeholder, it prompts on the console for a new name and then:
  - writes it to `name.txt`
  - sets the system hostname (`hostnamectl`)
  - ensures `/etc/hosts` has `127.0.1.1 <name>`
  - restarts Avahi and SSH
  - reboots

`post_install.bash` is a helper script to place `installation/system-patch/blitzprojstartup.bash` into `/usr/local/bin/` and make it runnable.

## Why the file structure looks like this

This repo is split into a few “layers” on purpose:

- **Top-level Docker + entry scripts**
  - `Dockerfile`, `compose.yml`, `Makefile`
  - These define how to run the build in a controlled environment.
- **Image plumbing**
  - `setup_image.bash`, `export_image_and_compress.bash`
  - These deal with loop devices, partitions, mounts, and cleanup.
- **Installation logic inside the image**
  - `installation/modules/`
  - These are the steps that run _inside_ the chroot and install software.
- **Per-device logic**
  - `installation/devices_and_distros/`
  - One small script per target device, plus a `devices.conf` that defines which OS image to use.
- **System patches**
  - `installation/system-patch/`
  - Files that should be copied into the image as-is (udev rules, etc.).
- **Docs**
  - `docs/` holds usage and “how it works” explanations.

This separation keeps changes safe:

- If you change device details, you usually only touch a device script or patch file.
- If you change what software gets installed, you usually only touch `installation/modules/`.
- If you change how images are mounted/exported, you usually only touch the image plumbing scripts.

## How to customize (common changes)

### Change the base OS image (or update versions)

Edit `installation/devices_and_distros/devices.conf`:

- Update `PI5_IMAGE_URL` to a newer Raspberry Pi OS image.
- Update `PI5_IMAGE_FILE` to match the downloaded filename.

### Change how much extra space is added

Edit `installation/devices_and_distros/build.bash`:

- `EXPAND_IMAGE_SIZE` controls how much space is appended to the image file before resizing partitions.

### Add a new device target

1. Add a new `*.bash` script in `installation/devices_and_distros/` (copy `pi5.bash` as a starting point).
2. Add `YOURDEVICE_IMAGE_FILE` and `YOURDEVICE_IMAGE_URL` to `devices.conf`.
3. Build it with:
   - `make build-for ARGS=yourdevice`

### Change what gets installed inside the image

Edit modules in `installation/modules/`:

- Add packages in `installation_common.bash`
- Change the B.L.I.T.Z branch or name defaults in `installation_blitz.bash`
- Change Autobahn install behavior in `installation_autobahn.bash`

### Change USB port naming rules

Edit `installation/system-patch/90-usb-port-names.rules`.

If you are targeting different hardware, keep the patch file but adjust the `KERNELS==` matches and symlink names.

### Change first-boot name behavior

Edit `installation/system-patch/blitzprojstartup.bash`:

- Change the placeholder default name (currently `blitz-pi-random-name-1234`)
- Change allowed characters (currently letters, numbers, `_`, `-`)
- Change what services restart on rename

If you do not want an interactive prompt, you can pre-create:

- `/opt/blitz/B.L.I.T.Z/system_data/name.txt`
  with the final name inside the image during the build.

## Where to start reading code

If you want to understand the build end-to-end, read in this order:

1. `installation/devices_and_distros/build.bash`
2. `installation/util/install_distro.bash`
3. `setup_image.bash`
4. `installation/devices_and_distros/pi5.bash`
5. `installation/modules/main_startup.bash` and the module scripts it calls
6. `export_image_and_compress.bash`
7. `installation/system-patch/blitzprojstartup.bash`
