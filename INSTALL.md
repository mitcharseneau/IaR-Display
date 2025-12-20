# INSTALL.md

## Overview

This document describes how to install and configure FullPageOS on a Raspberry Pi for use with iamresponding, including automatic page loading and installation of the IaR Helper Chromium extension.

These are the manual installation steps. This document does not use the provisioning script.

## Prerequisites

### Hardware

- Raspberry Pi
- Micro SD card
- Network connectivity

### Software and access

- Raspberry Pi Imager
- SSH access to the Raspberry Pi
- Optional: VNC client

## Install FullPageOS

FullPageOS must be installed before completing the steps below.

### Option 1: Raspberry Pi Imager (recommended)

1. Open Raspberry Pi Imager
2. Select Choose OS
3. Navigate to:
   - Other specific-purpose OS
   - Digital signage and kiosks
   - FullPageOS
   - FullPageOS (Stable)
4. Select your SD card
5. When prompted for user configuration, set the username to: `iar`
6. Write the image to the SD card

### Option 2: Manual download

1. Download FullPageOS from: <https://unofficialpi.org/Distros/FullPageOS/>
2. Open Raspberry Pi Imager
3. Select Use custom
4. Choose the downloaded image
5. Write the image to the SD card
6. Set the username to: `iar`

## Configure the FullPageOS boot partition

After imaging completes, remove and reinsert the SD card so it mounts on your computer.

### Set the kiosk URL

Open `fullpageos.txt` on the boot partition and replace the contents with:

```text
https://auth.iamresponding.com
```

### Update kernel cmdline flags

Open `cmdline.txt` on the boot partition and append the following to the end of the existing line:

```text
logo.nologo consoleblank=0 loglevel=0 quiet splash
```

Keep `cmdline.txt` as a single line.

### Optional: Replace the boot splash image

Replace `splash.png` on the boot partition with your department themed image.
Keep the same filename.

## First boot and SSH

1. Insert the SD card into the Raspberry Pi
2. Power on the device
3. Ensure it is connected to the network
4. SSH into the Raspberry Pi:

```bash
ssh iar@<raspberry_pi_ip>
```

## System update

Run:

```bash
sudo apt update
```

## Enable VNC and disable screen blanking

Run:

```bash
sudo raspi-config
```

Then set:

- Interface Options
  - VNC
    - Enable
- Display Options
  - Screen Blanking
    - Off

Exit and reboot if prompted.

## Install the extension folder

### Copy the extension to the Raspberry Pi

From your local machine, copy the extension folder to the Raspberry Pi:

```bash
scp -r "/path/to/extension" iar@<raspberry_pi_ip>:/home/iar/extension
```

Ensure the extension directory is owned by the `iar` user:

```bash
sudo chown -R iar:iar /home/iar/extension
```

## Create credentials.json

The extension includes `credentials.template.json`. Copy it to `credentials.json` and edit the values.

Agency, username, and password are case sensitive.

```bash
cp /home/iar/extension/credentials.template.json /home/iar/extension/credentials.json
nano /home/iar/extension/credentials.json
```

Set file permissions so only the `iar` user can read it:

```bash
chmod 600 /home/iar/extension/credentials.json
```

## Auto load the extension by wrapping Chromium

FullPageOS launches Chromium in kiosk mode, but loading an unpacked extension normally requires manual steps.

To make the extension load automatically, replace the Chromium launcher with a wrapper script that injects the extension flags.

### Determine which Chromium binary exists

Check for these files:

```bash
ls -l /usr/bin/chromium-browser /usr/bin/chromium 2>/dev/null
```

### Wrap chromium-browser (if it exists)

If `/usr/bin/chromium-browser` exists, run:

```bash
sudo mv /usr/bin/chromium-browser /usr/bin/chromium-browser.real
sudo tee /usr/bin/chromium-browser >/dev/null <<'EOF'
#!/usr/bin/env bash
# IAR_DISPLAY_WRAPPER
set -euo pipefail

EXT_DIR="/home/iar/extension"

exec /usr/bin/chromium-browser.real   --disable-extensions-except="${EXT_DIR}"   --load-extension="${EXT_DIR}"   "$@"
EOF
sudo chmod 755 /usr/bin/chromium-browser
```

### Wrap chromium (if it exists)

If `/usr/bin/chromium` exists, run:

```bash
sudo mv /usr/bin/chromium /usr/bin/chromium.real
sudo tee /usr/bin/chromium >/dev/null <<'EOF'
#!/usr/bin/env bash
# IAR_DISPLAY_WRAPPER
set -euo pipefail

EXT_DIR="/home/iar/extension"

exec /usr/bin/chromium.real   --disable-extensions-except="${EXT_DIR}"   --load-extension="${EXT_DIR}"   "$@"
EOF
sudo chmod 755 /usr/bin/chromium
```

## Make the desktop background match the boot splash

FullPageOS can briefly show the desktop before Chromium fully launches.
To make that transition seamless, copy the same image used for `splash.png` into the FullPageOS background path.

Copy your splash image to:

```bash
sudo cp /boot/firmware/splash.png /opt/custompios/background.png 2>/dev/null || sudo cp /boot/splash.png /opt/custompios/background.png
```

If `feh` is available, apply it immediately:

```bash
command -v feh >/dev/null 2>&1 && feh --bg-center /opt/custompios/background.png || true
```

## Reboot

Reboot to apply changes:

```bash
sudo reboot
```

## Verify

After reboot, verify:

- The device boots with your custom splash
- The desktop background matches the splash during startup
- Chromium launches in kiosk mode
- The IaR Helper extension is loaded automatically
- The iamresponding login page is displayed
