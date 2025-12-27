# IaR-Display

IaR-Display is a Raspberry Pi kiosk setup for displaying iamresponding using FullPageOS.
It automatically loads the iamresponding login page, installs a helper Chromium extension, applies a custom splash and background, and configures the system for unattended display use.

## What this project does

Once FullPageOS is installed, the provided provisioning script will:

- Configure FullPageOS to load the iamresponding URL
- Disable screen blanking
- Optionally enable or fully disable VNC
- If VNC is enabled, prompt for port and password configuration
- Apply a custom splash image and matching desktop background
- Install and auto load the IaR Helper Chromium extension
- Disable Chromium password save and autofill prompts
- Prompt for iamresponding credentials and generate credentials.json
- Log all command output to a local log file while showing clean installer status messages
- Reboot the system when complete

The only manual step is installing FullPageOS itself.

## Prerequisites

You must complete these steps before running the installer.

### Hardware

- Raspberry Pi
- Micro SD card
- Network connectivity

### Software and access

- Raspberry Pi Imager
- SSH access to the Raspberry Pi
- Optional: VNC client if remote access is enabled

## Install FullPageOS

FullPageOS must be installed before running the installer script.

Detailed instructions are available in INSTALL.md.
A brief summary is provided below.

### Option 1: Raspberry Pi Imager (recommended)

1. Open Raspberry Pi Imager
2. Select Choose OS
3. Navigate to:
   - Other specific-purpose OS
   - Digital signage and kiosks
   - FullPageOS
   - FullPageOS (Stable)
4. Select your SD card
5. When prompted for user configuration, set the username to:
   ```iar```
6. Write the image to the SD card

### Option 2: Manual download

1. Download FullPageOS from: https://unofficialpi.org/Distros/FullPageOS/
2. Open Raspberry Pi Imager
3. Select Use custom
4. Choose the downloaded image
5. Write the image to the SD card
6. Set the username to:
   ```iar```

## Boot and connect

1. Insert the SD card into the Raspberry Pi
2. Power on the device
3. Ensure it is connected to the network
4. SSH into the Raspberry Pi:
   ```ssh iar@<raspberry_pi_ip>```

## Quick install using the provisioning script

Once logged in via SSH, run the following commands.

### Clone the repository

```bash
git clone https://github.com/mitcharseneau/IaR-Display.git
cd IaR-Display
```

### Run the installer

```bash
sudo bash scripts/provision.sh
```

## Installer flow

The installer runs in clear, logical steps.

### Step 1: IaR configuration

You will be prompted for:

- IamResponding URL
- IamResponding agency name (case sensitive)
- IamResponding username (case sensitive)
- IamResponding password (case sensitive)

These values are used to configure FullPageOS and generate a secure credentials.json file for the Chromium extension.

### Step 2: Remote access (VNC)

After IaR setup is complete, you will be asked whether to enable VNC.

- If you choose yes, you will be prompted for:
  - VNC port (default can be accepted)
  - VNC password (case sensitive)
- If you choose no, VNC will be explicitly disabled and stopped

### Logging behavior

- All command output is written to:
  ```/var/log/iar-provision.log```
- The installer displays only structured status messages during execution
- If an error occurs, the log file should be consulted for details

When the installer finishes successfully, the Raspberry Pi will reboot automatically.

## After reboot

After reboot, the system will:

- Display the custom splash image during boot
- Show the same image as the desktop background during startup
- Automatically launch Chromium in kiosk mode
- Auto load the IaR Helper extension
- Suppress Chromium password save and autofill prompts
- Display the iamresponding login page

No additional manual configuration should be required.

## Manual installation

If you prefer to perform setup steps manually instead of using the installer script, see INSTALL.md for full instructions.

## License

See LICENSE for usage terms.
