## BlitzImageModifier

#### Disclaimer: README is written by AI and reviewed by me.

Create a preconfigured Raspberry Pi OS image (Pi 5, Bookworm arm64) with the Pinewood Robotics B.L.I.T.Z stack and Autobahn preinstalled. The build runs entirely inside Docker using QEMU, expands the base image, chroots into it to install packages and services, and then exports a compressed `.img.xz` ready to flash.

### What this does

- **Downloads** Raspberry Pi OS Lite (arm64 Bookworm) base image
- **Expands** the image filesystem to add space (+4 GB by default)
- **Chroots** into the image using QEMU to install software
- **Installs** common system deps, Rust toolchain, SSH, mDNS
- **Installs** B.L.I.T.Z (branch `merge-backend`) and Autobahn
- **Creates** the target login user inside the image before export (`ubuntu` / `ubuntu` by default)
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

The generated image includes a pre-created user account:

```text
username: ubuntu
password: ubuntu
```

To override it during image compilation:

```bash
make build-for pi5 BLITZ_USER=myuser BLITZ_PASSWORD=mypass
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

  - Runs `provision_user.bash` to create the target image user during compilation
  - Runs hardware script `pi5.bash` (installs udev rule)
  - Runs `installation_common.bash` (packages, Rust, SSH/mDNS enable)
  - Runs `installation_blitz.bash` (clones B.L.I.T.Z, `scripts/ui/install_on_system.sh` from the same checkout, with default name)
  - Runs `installation_autobahn.bash` (clones Autobahn, installs)
  - Runs `install_startup.bash` (installs first-boot naming)
  - Runs `finalize_permissions.bash` so `/opt/blitz` is owned by the target user

- `export_image_and_compress.bash`
  - Cleanly unmounts/breaks down loop/mapper devices
  - Renames the image, compresses to `.img.xz`, and copies into `./outputs/`

## First boot behavior

- The login account is already created during image compilation, before flashing.
- The login shell invokes `/usr/local/bin/blitzprojstartup.bash` for first-boot naming.
- On first boot, if the default name is still set, it will prompt on the console for a new device name and apply it (`hostnamectl`, `/etc/hosts`, restart Avahi/SSH), then reboot.
  - If you need a non-interactive first boot, pre-create `name.txt` inside the image at:
    - `/opt/blitz/B.L.I.T.Z/system_data/name.txt`

## Customization

- **Base image version**: in `Dockerfile` (`wget` URL). Update to a newer Raspberry Pi OS image if desired.
- **Extra space**: in `Dockerfile` (`truncate -s +4G ...`). Increase if you need more room preinstalled.
- **Hardware script**: currently `main_startup.bash` runs `pi5.bash`. Add your own script and change the argument in `setup_image.bash` (`main_startup.bash <your-script>.bash`).
- **Target image user**: pass `BLITZ_USER`, `BLITZ_PASSWORD`, `BLITZ_UID`, or `BLITZ_GID` to `make`. Defaults are `ubuntu`, `ubuntu`, `1000`, and `1000`.
- **BLITZ revision**: pass `BLITZ_REF=<branch/tag/commit>` to `make build-for pi5` or `make sim-build`. The installer and runtime use that same checkout. A commit SHA gives reproducible builds; `HEAD` follows upstream.
- **Default device name**: `installation_blitz.bash` (`DEFAULT_PI_NAME`). This is used on first boot before prompting.
- **udev rules**: edit `installation/system-patch/90-usb-port-names.rules` or adapt `pi5.bash` to your hardware.
- **Output filename**: `export_image_and_compress.bash` is invoked with `pi5_flash_image` by default (from `Dockerfile CMD`). Change it if you want a different name.

## Directory overview

- `Dockerfile`: Builder and orchestrator for the image creation
- `compose.yml`: Docker Compose service (privileged) that runs the pipeline
- `setup_image.bash`: Mounts/extends the downloaded image and enters chroot
- `main_startup.bash`: Orchestrates installs and setup inside the chroot
- `provision_user.bash`: Creates the target login account inside the image
- `finalize_permissions.bash`: Makes `/opt/blitz` owned by the target login account
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

## Updated BLITZ deployment integration

Images require BLITZ deployment **1.2.0 or later**. Image creation checks the module
catalog, typed launch contracts, watchdog discovery, installation root, and offline
transfer tools. An older or incompatible source checkout fails the build with an
error. Changes in your local BLITZ repository must be published before using a
remote revision; selecting a branch does not include uncommitted changes.

```bash
make build-for pi5 BLITZ_SOURCE_DIR=/path/to/your/updated/BLITZ
# Or use an already-published revision:
make build-for pi5 BLITZ_REF=<published-commit>
make sim-build BLITZ_REF=<published-commit>
```

For Pi image builds, `make build-for pi5 BLITZ_SOURCE_DIR=/path/to/BLITZ` mounts
the host source read-only into the build container and chroot. The installer
also accepts `BLITZ_SOURCE_DIR` directly inside a prepared build environment. It copies working-tree changes and excludes virtual environments,
build artifacts, website files, `.env` files, and the developer's device name.
This option is for an environment where the source is already mounted; passing a
host path to `make sim-build` does not mount that path automatically.

The target layout stays:

```text
/opt/blitz/B.L.I.T.Z/
├── .venv/                 # Shared Python environment, provisioned online
├── watchdog/             # Target process manager
├── system_data/           # Device name and watchdog configuration
└── backend/               # One active backend bundle
    ├── deployment/        # Preserved deployment tooling
    ├── python/<module>/
    ├── cpp/<module>/
    ├── rust/<module>/
    ├── lib/<module>/      # Namespaced compiled libraries
    └── resources/<module>/
```

The image is provisioned online once. Application dependency compilation and
Docker caching happen on the developer's computer; the target receives bundles
and installs Python dependencies from bundled wheels offline. Module programs
receive runtime paths through environment variables and require no BLITZ CLI flags
by default. `BLITZ_USER` also selects the watchdog service account, matching the
ownership established by `finalize_permissions.bash`.

The simulator bridge obtains discovery properties from the installed watchdog,
including distro, Python version, architecture, and CUDA capabilities. The
simulator describes its own Linux container, not Raspberry Pi hardware or a real
NVIDIA GPU. You can select it directly without mDNS:

```bash
# In your application project, using that project's updated deploy.py:
.venv/bin/python backend/deploy.py --device blitz-sim-1.local:5000
```

Integration regression tests (using BLITZ's test environment):

```bash
BLITZ_SOURCE_DIR=/path/to/BLITZ /path/to/BLITZ/.venv/bin/python -m pytest tests/ -q
```

To recheck an installed image, run from its BLITZ root with the image modifier's
`installation/util/check_blitz_runtime.py` available:

```bash
BLITZ_PATH="$PWD" .venv/bin/python /workspace/installation/util/check_blitz_runtime.py
```

### Pi 5 build verification

The Bookworm image's boot partition is mounted at `/boot/firmware` during
provisioning. Services are enabled for first boot; start/reload commands run only
when a systemd manager is available. Chroot DNS overrides are restored before
export, and failed setup cleans up the mounts and loop device it created.

The final `validate_image.bash` check verifies watchdog startup imports, enabled
SSH/mDNS/watchdog/Autobahn services, the Autobahn executable/configuration,
startup naming, and ownership by the configured login user. A successful image
build still does not prove hardware boot, USB peripherals, or the device's actual
network connection; those require flashing and booting a Pi.

See [Pi 5 validation results](docs/Pi5-validation.md) for the actual image build,
exported-image runtime checks, and remaining hardware checks.

## Pi 5 header and CSI camera support

Pi 5 builds now enable GPIO/I2C/SPI access and CSI camera auto-detection, install
Picamera2/libcamera, and expose their native Python bindings to the shared BLITZ
environment. See [Pi 5 hardware setup and examples](docs/Pi5-hardware.md).
