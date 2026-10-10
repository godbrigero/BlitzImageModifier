# Pi 5 GPIO and ribbon cameras

Pi 5 images provision both the header interfaces and the modern CSI camera stack.
A GPIO pin or camera must still be connected and used by application code; the
installer does not drive outputs or start capturing automatically.

## What the image enables

- GPIO character-device access through libgpiod/lgpio, with GPIO Zero available.
- Header I2C (`dtparam=i2c_arm=on`) and SPI (`dtparam=spi=on`).
- `i2c-dev` at boot, `i2c-tools`, and Python `smbus`/`spidev` bindings.
- CSI camera auto-detection (`camera_auto_detect=1`) and headless `rpicam` tools,
  libcamera, and Picamera2.
- The configured login/watchdog user belongs to `gpio`, `i2c`, `spi`, `video`, and
  `render`. Group-based udev rules allow background service access to GPIO, I2C,
  SPI, V4L2, media, and DMA-heap nodes without running application processes as root.

The Pi's boot configuration retains its existing settings, with an idempotent
managed BLITZ section appended under `[all]`. Interface changes take effect at boot.
Enabling I2C/SPI assigns their header pins to those interfaces; choose other pins
for ordinary GPIO outputs.

## Python packages and deployment

The Pi image's BLITZ virtual environment uses the distro's Python 3.11 and is
created with `--system-site-packages`. This exposes the distro's native camera
bindings to watchdog-launched programs. Picamera2 recommends this arrangement
because libcamera is provided by the OS rather than pip. See the
[Picamera2 manual](https://datasheets.raspberrypi.com/camera/picamera2-manual.pdf).

Keep the single application `requirements.txt` for other Python dependencies.
The image already supplies `picamera2`, `libcamera`, `gpiozero`, `lgpio`, `gpiod`,
`smbus`, and `spidev`; they do not need a second dependency manifest. Keep pip
packages compatible with the image's native bindings—especially NumPy and
packages compiled against its ABI. A pip install can shadow a system package.
BLITZ currently requires NumPy 2 through its Autobahn client. Online image
provisioning installs the upstream `simplejpeg==1.9.0` wheel in the shared venv,
replacing Bookworm's NumPy-1-built JPEG extension for that environment. Build
validation performs a JPEG encode/decode round trip to catch ABI mismatches.
Offline deployment preserves this virtual environment and installs application
wheels into it.

### GPIO example: dynamically select the Pi 5 header controller

Place this in a module such as `backend/python/led/main.py`, or keep the reusable
factory setup in `backend/python/common/`. Linux gpiochip numbers can change with
kernel versions, so select the RP1 controller by label rather than hardcoding a
chip number. GPIO Zero supports an explicit lgpio chip selection; see its
[pin-factory documentation](https://gpiozero.readthedocs.io/en/stable/api_pins.html).

```python
import re
import subprocess
from time import sleep

from gpiozero import Device, LED
from gpiozero.pins.lgpio import LGPIOFactory

chips = subprocess.check_output(["gpiodetect"], text=True)
match = re.search(r"^gpiochip(\d+)\s+\[pinctrl-rp1\]", chips, re.MULTILINE)
if match is None:
    raise RuntimeError("Pi 5 RP1 GPIO controller not found")
Device.pin_factory = LGPIOFactory(chip=int(match.group(1)))

# GPIO17 uses BCM numbering (physical header pin 11).
with LED(17) as led:
    led.on()
    sleep(1)
```

Connect an LED with an appropriate resistor. Header GPIO uses 3.3 V logic.

### CSI camera example

Put this in `backend/python/camera/main.py`:

```python
from time import sleep
from picamera2 import Picamera2

with Picamera2(camera_num=0) as camera:
    camera.configure(camera.create_still_configuration())
    camera.start()
    sleep(2)  # Let exposure and white balance settle.
    camera.capture_file("/tmp/camera.jpg")
```

For continuous processing, use `capture_array()` on a configured running camera.
Choose a camera from `Picamera2.global_camera_info()` if more than one is attached;
list indices are not a permanent mapping to CAM/DISP connectors.

Official supported Raspberry Pi camera modules are auto-detected. A third-party
sensor may require its own driver and device-tree overlay; select those when you
choose the camera. See the official
[camera documentation](https://www.raspberrypi.com/documentation/computers/camera_software.html).
Pi 5 uses 22-pin CAM/DISP connectors, so older 15-pin camera boards require the
appropriate Pi 5 ribbon/adapter cable. Power off before connecting the ribbon.

## Check after flashing

Run as the configured normal user:

```bash
id
ls -l /dev/gpiochip* /dev/i2c-* /dev/spidev*
gpiodetect
rpicam-hello --list-cameras
/opt/blitz/B.L.I.T.Z/.venv/bin/python -c 'from picamera2 import Picamera2; print(Picamera2.global_camera_info())'
```

An empty camera list means no supported camera was detected; installing the
libraries does not prove the cable/sensor works. Image-build validation imports
all hardware Python bindings inside BLITZ's actual environment and checks settings
and groups. Electrical operation, camera detection, and capture require a booted Pi.
