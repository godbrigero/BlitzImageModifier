# Pi 5 image validation

Validation performed on 2026-10-09 using the local updated BLITZ checkout.

## Verified

- Completed `make build-for pi5 BLITZ_SOURCE_DIR=/path/to/BLITZ`.
- Exported `outputs/pi5_flash_image.img` with BLITZ deployment 1.2.0.
- Inspected the exported image in a read-only ARM64 chroot with temporary writable
  storage for the module smoke test.
- Confirmed Debian 12, ARM64, glibc 2.36, and the watchdog's Python 3.11 environment.
  The additional pyenv Python installation does not change this system-Python
  virtual environment; deployment uses the version advertised by watchdog.
- Verified imports of the watchdog entrypoint and the updated deployment APIs.
- Verified enabled watchdog, Autobahn, SSH, and Avahi units, runtime ownership,
  Autobahn executable/configuration, and the first-boot naming script.
- Confirmed the build's temporary DNS override was restored.
- Compiled `libvision.so` inside that image's userspace and launched Python through
  its installed watchdog. Python called the native function and obtained 42.
  Runtime paths were supplied through the environment; no BLITZ CLI flags were
  injected.
- Passed 10 image-modifier integration/flow tests, 77 targeted BLITZ regression
  tests, and 7 actual Docker native-bundle/runtime tests.

The final build gate is `installation/modules/validate_image.bash`, which runs
`check_blitz_runtime.py` and `smoke_blitz_module.py`. Smoke-test files are temporary
and are removed after the test.

## Fixed during this verification

- Mount Bookworm's boot partition at `/boot/firmware`, as described in the
  [Raspberry Pi documentation](https://www.raspberrypi.com/documentation/computers/configuration.html).
- Enable services without requiring a running systemd/udev manager in the chroot.
- Preserve the startup source file across repeated image builds.
- Keep naming validation errors out of the resulting device name.
- Restore DNS configuration and clean up failed setup mounts/loop devices.
- Load Rust's environment explicitly in the Autobahn installation shell and fail
  on build/install errors.
- Support a read-only local BLITZ checkout through Compose and the chroot.
- Use `docker compose run --build --rm` so a failed build returns a failing status.

## Remaining hardware validation

This verifies image creation and target userspace execution. It does not emulate
Raspberry Pi firmware or prove physical boot, USB peripherals, DHCP/Wi-Fi, or
network discovery on the actual device. Flash the image to a Pi 5, log in, give it
a unique name, and check:

```bash
systemctl is-active blitz-startup autobahn ssh avahi-daemon
journalctl -u blitz-startup -n 100 --no-pager
curl --fail http://localhost:5000/get/system/identity
```

At validation time, upstream's deployment marker was still 1.0.21. Build with the
local updated checkout, or publish these changes and select that published
revision with `BLITZ_REF`. A default remote build intentionally rejects the older
runtime.

## GPIO and CSI image update

Pi 5 builds additionally provision GPIO/I2C/SPI, camera auto-detection, and
Picamera2/libcamera in the shared Python environment. See
[hardware setup](Pi5-hardware.md) for examples and device-level checks.

The first hardware build correctly failed its import gate on the distro JPEG
extension's NumPy ABI mismatch. Provisioning now installs a compatible binary
JPEG wheel and checks actual encode/decode operations, in addition to hardware
imports, groups, udev rules, and boot settings. No camera is opened and no GPIO
outputs are driven during image creation.

The corrected hardware image was rebuilt and exported successfully. Its exported
root and boot partitions were then inspected read-only. Camera/GPIO imports, the
JPEG round trip, and the watchdog/shared-library smoke test also passed as the
normal `ubuntu` account. The updated image-modifier suite passed 14 tests.
GPIO signals and physical camera capture remain untested without a Pi and sensor.
