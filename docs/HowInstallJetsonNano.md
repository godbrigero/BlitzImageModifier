# Jetson Nano installation instructions

These image links are for **Jetson Orin Nano**, not the original Jetson Nano.
Use the NVIDIA image appropriate to your actual board.

# Step 1: install the base image

use either this link with instructions:
https://developer.nvidia.com/embedded/jetpack-sdk-62

or this one to directly download the .zip file:
https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/jp62-orin-nano-sd-card-image.zip

# Step 2: flash the image to the SD card

Use Balena Etcher to flash the image to the SD card. No need to unzip the file btw.

# Step 3

Plug in the SD card into the Jetson Nano and power it on. Note that you will need to connect the jetson nano to a power source and a monitor at this point.

# Step 4: Setting up the Jetson Nano

1. Accept all the terms/conditions
2. Select "English" as the language
3. Select "English (US)" as the keyboard layout
4. Select "Los Angeles" as the time zone
5. Choose a device/display name.
6. Choose a computer hostname.
7. Choose your normal login username, such as `jetson`.
8. Set your login password. The live installer preserves your account/password.
9. In the "APP Partition Size" field set the maximum accepted size. So if it says "Current size: 21386 MB, Maximum size: 59412 MB." then set it to "59412".
10. Do not install chromium browser.

# Step 5: Inside Jetson Nano

1. Login to the "ubuntu" user.
2. Select "settings" from the bottom left corner.
3. Go to "WiFi" tab and connect to the wifi network.

# Step 6: Install the BlitzImageModifier

1. Open Terminal and run the following command to install git:

```bash
sudo apt-get update
sudo apt-get install git
```

2. Clone the BlitzImageModifier repository:

```bash
git clone https://github.com/godbrigero/BlitzImageModifier.git
```

3. cd into the BlitzImageModifier repository and run the jetson_nano.bash script:

Run as your normal login user (for example `jetson`), **without sudo**. The
script elevates individual system operations and uses that login user for the
watchdog service. Do not rename or replace your existing user with `ubuntu`.

Update ImageModifier before installation; old copies downloaded an installer
separately from BLITZ and could fail with `scripts/install.sh: No such file or directory`.

The maintained installation scripts currently live in
`https://github.com/godbrigero/BlitzImageModifier.git`. The older
`PinewoodRobotics/BlitzImageModifier` repository still invokes the removed
`scripts/install.sh`; pulling that repository does not retrieve these fixes.
Check the repository URL with `git remote -v`.

```bash
cd BlitzImageModifier
git pull --ff-only
bash ./installation/extra/jetson_nano.bash
```

### Retrying the missing installer failure

If the checkout came from `PinewoodRobotics/BlitzImageModifier`, clone the
maintained repository into a separate folder and use its installer:

```bash
cd ..
git clone https://github.com/godbrigero/BlitzImageModifier.git BlitzImageModifier-current
cd BlitzImageModifier-current
bash ./installation/extra/jetson_nano.bash
```

This preserves the previous ImageModifier folder and the installed
`/opt/blitz/B.L.I.T.Z` checkout. It does not require reflashing the Jetson.

After updating ImageModifier, rerun the same command. The Jetson script reuses
an existing BLITZ checkout without deleting it, preserves an existing device
name, skips rebuilding an already installed Python version, and reuses the
Autobahn source folder. The installed BLITZ tree must contain
`scripts/ui/install_on_system.sh`, `scripts/setup.sh`, and the current module API.
An incompatible tree fails with an explicit upgrade instruction.

If `/opt/blitz/B.L.I.T.Z` is an older **Git checkout**, update that checkout to
the intended current BLITZ revision first. For an unmodified checkout tracking
its normal branch, this can be done with:

```bash
git -C /opt/blitz/B.L.I.T.Z status --short
git -C /opt/blitz/B.L.I.T.Z pull --ff-only
bash ./installation/extra/jetson_nano.bash
```

Preserve local changes before updating; do not delete the folder or force-reset
it. A detached or locally copied checkout needs your usual BLITZ updater or an
explicit revision update. Resume preserves that checkout; `BLITZ_REF` and
`BLITZ_SOURCE_DIR` only select source for a fresh installation.

4. Post-install:

login into the ubuntu user and set the ubuntu name as whatever you want. The default behavior should be that the terminal opens to **full screen** (which means that you can exit the terminal if you want) once you login. You will have to log into the Jetson Nano again and set the name as prompted by the system.

# You're done!
