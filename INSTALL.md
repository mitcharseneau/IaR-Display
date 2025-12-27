# INSTALL.md

## Overview

This document describes how to manually install and configure a Raspberry Pi running FullPageOS for use with iamresponding.

These steps replicate everything performed by the automated provisioning script, including kiosk configuration, extension loading, credential handling, VNC configuration, splash and background setup, and Chromium policy changes.

No part of this document relies on the provisioning script.

## Prerequisites

### Hardware

- Raspberry Pi
- Micro SD card
- Network connectivity

### Software and access

- Raspberry Pi Imager
- SSH access to the Raspberry Pi
- Optional: VNC client if remote access is desired

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
5. When prompted for user configuration, set the username to: ```iar```
6. Write the image to the SD card

### Option 2: Manual download

1. Download FullPageOS from:
   <https://unofficialpi.org/Distros/FullPageOS/>
2. Open Raspberry Pi Imager
3. Select Use custom
4. Choose the downloaded image
5. Write the image to the SD card
6. Set the username to: ```iar```

## Configure the FullPageOS boot partition

After imaging completes, remove and reinsert the SD card so it mounts on your computer.

### Set the kiosk URL

Open `fullpageos.txt` on the boot partition and replace its contents with:

```text
https://auth.iamresponding.com
```

### Update kernel cmdline flags

Open `cmdline.txt` on the boot partition and append the following flags to the end of the existing line:

```text
logo.nologo consoleblank=0 loglevel=0 quiet splash
```

Keep `cmdline.txt` as a single line.

### Optional: Replace the boot splash image

Replace `splash.png` on the boot partition with your department themed image.
Keep the same filename.

## First boot and SSH access

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

## Disable screen blanking

Disable display blanking so the kiosk remains visible.

```bash
sudo raspi-config
```

Then set:

- Display Options
  - Screen Blanking
    - Off

Exit and reboot if prompted.

## Optional: Configure VNC

You may either enable VNC with a custom port and password or ensure it is fully disabled.

### Enable VNC

1. Enable VNC:

```bash
sudo raspi-config
```

Navigate to:

- Interface Options
  - VNC
    - Enable

2. Configure the VNC port and authentication.

Create or edit the RealVNC configuration file:

```bash
sudo mkdir -p /etc/vnc/config.d
sudo nano /etc/vnc/config.d/vncserver-x11
```

Add or ensure the following entries exist:

```text
Authentication=VncAuth
RfbPort=5900
```

3. Set the VNC service password:

```bash
vncpasswd -service
```

4. Restart the VNC service:

```bash
sudo systemctl restart vncserver-x11-serviced.service
```

### Disable VNC completely

If you do not want VNC enabled:

```bash
sudo raspi-config nonint do_vnc 1
sudo systemctl disable --now vncserver-x11-serviced.service 2>/dev/null || true
sudo systemctl disable --now wayvnc.service 2>/dev/null || true
```

## Install the IaR Helper Chromium extension

### Copy the extension directory

From your local machine, copy the extension folder to the Raspberry Pi:

```bash
scp -r /path/to/extension iar@<raspberry_pi_ip>:/home/iar/extension
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

### Determine which Chromium binary exists

```bash
ls -l /usr/bin/chromium-browser /usr/bin/chromium 2>/dev/null
```

### Wrap chromium-browser (if it exists)

```bash
sudo mv /usr/bin/chromium-browser /usr/bin/chromium-browser.real
sudo tee /usr/bin/chromium-browser >/dev/null <<'EOF'
#!/usr/bin/env bash
# IAR_DISPLAY_WRAPPER
set -euo pipefail

EXT_DIR="/home/iar/extension"

exec /usr/bin/chromium-browser.real \
  --disable-extensions-except="${EXT_DIR}" \
  --load-extension="${EXT_DIR}" \
  "$@"
EOF
sudo chmod 755 /usr/bin/chromium-browser
```

### Wrap chromium (if it exists)

```bash
sudo mv /usr/bin/chromium /usr/bin/chromium.real
sudo tee /usr/bin/chromium >/dev/null <<'EOF'
#!/usr/bin/env bash
# IAR_DISPLAY_WRAPPER
set -euo pipefail

EXT_DIR="/home/iar/extension"

exec /usr/bin/chromium.real \
  --disable-extensions-except="${EXT_DIR}" \
  --load-extension="${EXT_DIR}" \
  "$@"
EOF
sudo chmod 755 /usr/bin/chromium
```

## Disable Chromium password save and autofill prompts

Create a managed Chromium policy:

```bash
sudo mkdir -p /etc/chromium/policies/managed
sudo nano /etc/chromium/policies/managed/iar-display-policy.json
```

Add the following:

```json
{
  "PasswordManagerEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false
}
```

## Match desktop background to boot splash

```bash
sudo cp /boot/firmware/splash.png /opt/custompios/background.png 2>/dev/null || \
sudo cp /boot/splash.png /opt/custompios/background.png
```

If `feh` is available, apply it immediately:

```bash
command -v feh >/dev/null 2>&1 && feh --bg-center /opt/custompios/background.png || true
```

## Reboot

```bash
sudo reboot
```

## Verify

After reboot, verify:

- The device boots with your custom splash
- The desktop background matches the splash during startup
- Chromium launches in kiosk mode
- The IaR Helper extension is loaded automatically
- Chromium does not prompt to save passwords
- The iamresponding login page is displayed
