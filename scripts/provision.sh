#!/usr/bin/env bash
set -euo pipefail

PI_USER_DEFAULT="iar"
WORKDIR_DEFAULT="/opt/iar-display"
TARGET_URL_DEFAULT="https://auth.iamresponding.com"
VNC_PORT_DEFAULT="5900"

log() { printf '%s\n' "[provision] $*"; }
err() { printf '%s\n' "[provision][error] $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run with sudo."
    err "Example: sudo bash $0"
    exit 1
  fi
}

script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
}

repo_root_from_script() {
  local sd
  sd="$(script_dir)"
  cd -- "${sd}/.." >/dev/null 2>&1
  pwd
}

prompt() {
  local __var="$1"
  local __msg="$2"
  local __default="${3:-}"
  local __val=""

  if [[ -n "${__default}" ]]; then
    read -r -p "${__msg} [${__default}]: " __val || true
    __val="${__val:-$__default}"
  else
    read -r -p "${__msg}: " __val || true
  fi

  printf -v "${__var}" '%s' "${__val}"
}

ensure_user_exists() {
  local user="$1"
  if ! id -u "$user" >/dev/null 2>&1; then
    err "User '${user}' does not exist."
    err "Create it first, or rerun and choose an existing user."
    exit 1
  fi
}

boot_root() {
  if [[ -d /boot/firmware ]]; then
    printf '%s' "/boot/firmware"
  else
    printf '%s' "/boot"
  fi
}

system_update() {
  # No package installs. This matches the manual instruction "sudo apt update".
  if command -v apt-get >/dev/null 2>&1; then
    log "Running system update: apt-get update"
    apt-get update -y || true
  else
    log "apt-get not found, skipping system update."
  fi
}

set_fullpageos_url() {
  local url="$1"
  local br fp
  br="$(boot_root)"
  fp="${br}/fullpageos.txt"

  if [[ ! -f "$fp" ]]; then
    err "Could not find ${fp}."
    err "FullPageOS may be different on this image. Check your boot partition."
    exit 1
  fi

  log "Setting FullPageOS URL in ${fp}..."
  printf '%s\n' "$url" > "$fp"
}

append_cmdline_flags() {
  local br cmd
  br="$(boot_root)"
  cmd="${br}/cmdline.txt"

  if [[ ! -f "$cmd" ]]; then
    err "Could not find ${cmd}."
    exit 1
  fi

  log "Updating ${cmd} flags..."
  local current
  current="$(cat "$cmd")"

  # Keep cmdline.txt as one line, append any missing flags
  for f in logo.nologo consoleblank=0 loglevel=0 quiet splash; do
    if [[ "$current" != *"$f"* ]]; then
      current="${current} ${f}"
    fi
  done

  printf '%s' "$current" > "$cmd"
}

maybe_install_splash() {
  local repo_dir="$1"
  local br dst_splash src

  br="$(boot_root)"
  dst_splash="${br}/splash.png"
  src="${repo_dir}/assets/splash.png"

  if [[ ! -f "$src" ]]; then
    log "No assets/splash.png found, skipping splash and background replacement."
    return 0
  fi

  log "Replacing boot splash image at ${dst_splash}..."
  cp -f "$src" "$dst_splash"

  # FullPageOS uses /opt/custompios/background.png as the desktop background.
  # Copy the same image there so the pre-kiosk desktop matches the boot splash.
  if [[ -d /opt/custompios ]]; then
    log "Replacing FullPageOS desktop background at /opt/custompios/background.png..."
    cp -f "$src" /opt/custompios/background.png

    # Apply immediately if feh exists. Otherwise it will apply next time the OS sets it.
    if command -v feh >/dev/null 2>&1; then
      feh --bg-center /opt/custompios/background.png >/dev/null 2>&1 || true
    fi
  else
    log "/opt/custompios not found, skipping desktop background replacement."
  fi
}

disable_screen_blanking() {
  if ! command -v raspi-config >/dev/null 2>&1; then
    log "raspi-config not found, skipping screen blanking configuration."
    return 0
  fi

  log "Disabling screen blanking..."
  raspi-config nonint do_blanking 1 || true
}

systemctl_try_disable_now() {
  local unit="$1"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${unit}"; then
      log "Disabling and stopping ${unit}..."
      systemctl disable --now "${unit}" >/dev/null 2>&1 || true
    fi
  fi
}

systemctl_try_restart() {
  local unit="$1"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${unit}"; then
      log "Restarting ${unit}..."
      systemctl restart "${unit}" >/dev/null 2>&1 || true
    fi
  fi
}

ensure_vnc_disabled() {
  # Best-effort disable across Pi OS variants (RealVNC or WayVNC).
  if command -v raspi-config >/dev/null 2>&1; then
    log "Disabling VNC via raspi-config (best effort)..."
    raspi-config nonint do_vnc 1 >/dev/null 2>&1 || true
  else
    log "raspi-config not found, cannot toggle VNC via raspi-config."
  fi

  # RealVNC (X11) service mode
  systemctl_try_disable_now "vncserver-x11-serviced.service"
  # WayVNC (Wayland) used on some newer images
  systemctl_try_disable_now "wayvnc.service"
}

write_realvnc_config() {
  local port="$1"
  local cfg="/etc/vnc/config.d/vncserver-x11"

  mkdir -p /etc/vnc/config.d

  # Keep existing settings where possible, but ensure Authentication and RfbPort are set.
  # RealVNC config format is "Key=Value" per line.
  local tmp
  tmp="$(mktemp)"

  if [[ -f "$cfg" ]]; then
    cp -f "$cfg" "$tmp"
  else
    : > "$tmp"
  fi

  # Drop any existing Authentication/RfbPort lines then append ours.
  grep -v -E '^(Authentication|RfbPort)=' "$tmp" > "${tmp}.filtered" || true
  mv -f "${tmp}.filtered" "$tmp"

  cat >> "$tmp" <<EOF
Authentication=VncAuth
RfbPort=${port}
EOF

  install -m 644 "$tmp" "$cfg"
  rm -f "$tmp"
}

read_vnc_password_plaintext() {
  local __outvar="$1"
  local p1=""
  local p2=""

  while true; do
    read -r -p "VNC password (min 6 chars, plaintext): " p1 || true
    if [[ -z "$p1" ]]; then
      err "Password cannot be empty."
      continue
    fi
    if [[ "${#p1}" -lt 6 ]]; then
      err "Password must be at least 6 characters."
      continue
    fi

    read -r -p "Confirm VNC password (plaintext): " p2 || true
    if [[ "$p1" != "$p2" ]]; then
      err "Passwords did not match. Try again."
      continue
    fi

    # For compatibility with legacy VNC auth implementations, only the first 8
    # characters may be significant. Truncate to 8 to avoid surprises.
    if [[ "${#p1}" -gt 8 ]]; then
      log "Note: truncating VNC password to first 8 characters for compatibility."
      p1="${p1:0:8}"
    fi

    printf -v "${__outvar}" '%s' "$p1"
    return 0
  done
}

configure_vnc_if_requested() {
  local enable_vnc="$1"
  local port="$2"
  local password="$3"

  disable_screen_blanking

  if [[ "${enable_vnc,,}" != "y" ]]; then
    log "VNC not enabled (you chose no). Ensuring it is disabled..."
    ensure_vnc_disabled
    return 0
  fi

  if ! command -v raspi-config >/dev/null 2>&1; then
    err "raspi-config not found; cannot enable VNC reliably on this image."
    err "Install/enable VNC manually or ensure raspi-config is available."
    exit 1
  fi

  log "Enabling VNC via raspi-config..."
  raspi-config nonint do_vnc 0 || true

  # Prefer configuring RealVNC if the tooling is present.
  if command -v vncpasswd >/dev/null 2>&1; then
    log "Configuring RealVNC (password auth and port)..."
    write_realvnc_config "$port"

    log "Setting VNC service-mode password..."
    # vncpasswd -service prompts twice. Feed via stdin.
    printf '%s\n%s\n' "$password" "$password" | vncpasswd -service >/dev/null 2>&1 || {
      err "Failed to set VNC password with 'vncpasswd -service'."
      err "If this image uses WayVNC instead of RealVNC, password setup differs."
      exit 1
    }

    systemctl_try_restart "vncserver-x11-serviced.service"
  else
    err "vncpasswd not found; cannot set a dedicated VNC password."
    err "This image may be using WayVNC, or RealVNC tooling is missing."
    err "Either install the appropriate VNC server tooling, or use SystemAuth."
    exit 1
  fi

  log "VNC enabled. Direct connections should use port ${port}."
}

copy_tree_clean() {
  # Remove destination and copy source tree without additional dependencies.
  local src="$1"
  local dst="$2"

  rm -rf "$dst"
  mkdir -p "$dst"
  cp -a "${src}/." "$dst/"
}

sync_repo_to_workdir() {
  local repo_dir="$1"
  local workdir="$2"

  log "Syncing repo to ${workdir}..."
  mkdir -p "$workdir"
  copy_tree_clean "$repo_dir" "$workdir"
}

install_extension() {
  local repo_dir="$1"
  local pi_user="$2"
  local dst="/home/${pi_user}/extension"

  if [[ ! -d "${repo_dir}/extension" ]]; then
    err "Expected '${repo_dir}/extension' to exist."
    err "Add your extension folder to the repo and rerun."
    exit 1
  fi

  log "Copying extension folder to ${dst}..."
  mkdir -p "/home/${pi_user}"
  copy_tree_clean "${repo_dir}/extension" "$dst"
  chown -R "${pi_user}:${pi_user}" "$dst"
}

json_escape_minimal() {
  # Minimal JSON escape for backslash and double quotes.
  # Does not handle newlines or other control chars.
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

create_credentials() {
  local pi_user="$1"
  local ext_dir="/home/${pi_user}/extension"
  local template="${ext_dir}/credentials.template.json"
  local creds="${ext_dir}/credentials.json"

  if [[ ! -f "$template" ]]; then
    err "Missing ${template}."
    err "Your extension folder must include credentials.template.json."
    exit 1
  fi

  log "Credentials are case sensitive: agency, username, and password."

  local agency iar_user iar_pass
  prompt agency "IaR agency (case sensitive)" ""
  prompt iar_user "IaR username (case sensitive)" ""
  prompt iar_pass "IaR password (case sensitive)" ""

  cp -f "$template" "$creds"

  local a u p
  a="$(json_escape_minimal "$agency")"
  u="$(json_escape_minimal "$iar_user")"
  p="$(json_escape_minimal "$iar_pass")"

  umask 077
  cat > "$creds" <<EOF
{
  "agency": "${a}",
  "username": "${u}",
  "password": "${p}"
}
EOF

  chown "${pi_user}:${pi_user}" "$creds"
  chmod 600 "$creds"
}

install_chromium_wrapper() {
  # Wrapping chromium is more reliable than patching FullPageOS scripts because
  # the chromium command may be constructed dynamically.
  local pi_user="$1"
  local ext_dir="/home/${pi_user}/extension"

  local targets=(/usr/bin/chromium-browser /usr/bin/chromium)
  local installed_any="n"

  for t in "${targets[@]}"; do
    if [[ ! -e "$t" ]]; then
      continue
    fi

    if head -n 5 "$t" 2>/dev/null | grep -q "IAR_DISPLAY_WRAPPER"; then
      log "Wrapper already installed for ${t}"
      installed_any="y"
      continue
    fi

    local backup="${t}.real"
    if [[ -e "$backup" ]]; then
      log "Backup already exists: ${backup}"
    else
      log "Backing up ${t} -> ${backup}"
      mv "$t" "$backup"
    fi

    log "Installing wrapper at ${t}"
    cat > "$t" <<EOF
#!/usr/bin/env bash
# IAR_DISPLAY_WRAPPER
set -euo pipefail

EXT_DIR="${ext_dir}"

exec "${backup}" \\
  --disable-extensions-except="\${EXT_DIR}" \\
  --load-extension="\${EXT_DIR}" \\
  "\$@"
EOF

    chmod 755 "$t"
    installed_any="y"
  done

  if [[ "$installed_any" != "y" ]]; then
    err "Could not find chromium-browser or chromium under /usr/bin to wrap."
    err "Extension will not auto-load. You can still load it manually."
    return 1
  fi

  log "Chromium wrapper installed. Extension should auto-load on next launch."
  return 0
}

main() {
  require_root

  local repo_dir
  repo_dir="$(repo_root_from_script)"

  if [[ ! -f "${repo_dir}/README.md" ]]; then
    err "Could not locate repo root from script location."
    err "Keep the script at scripts/provision.sh inside the repo."
    exit 1
  fi

  log "Using local repo at: ${repo_dir}"

  local pi_user enable_vnc target_url
  prompt pi_user "Pi user (owner of /home/<user>/extension)" "${PI_USER_DEFAULT}"
  prompt enable_vnc "Enable VNC? (y/n)" "y"
  prompt target_url "iamresponding URL" "${TARGET_URL_DEFAULT}"

  ensure_user_exists "$pi_user"

  local vnc_port=""
  local vnc_password=""
  if [[ "${enable_vnc,,}" == "y" ]]; then
    prompt vnc_port "VNC port (direct TCP listen port)" "${VNC_PORT_DEFAULT}"
    if [[ -z "$vnc_port" ]]; then
      vnc_port="${VNC_PORT_DEFAULT}"
    fi
    if ! [[ "$vnc_port" =~ ^[0-9]+$ ]] || (( vnc_port < 1 || vnc_port > 65535 )); then
      err "Invalid VNC port: ${vnc_port}"
      exit 1
    fi

    read_vnc_password_plaintext vnc_password
  fi

  system_update

  # VNC and screen blanking handling:
  configure_vnc_if_requested "$enable_vnc" "${vnc_port:-$VNC_PORT_DEFAULT}" "${vnc_password:-}"

  sync_repo_to_workdir "$repo_dir" "$WORKDIR_DEFAULT"

  set_fullpageos_url "$target_url"
  append_cmdline_flags
  maybe_install_splash "${WORKDIR_DEFAULT}"

  install_extension "${WORKDIR_DEFAULT}" "$pi_user"
  create_credentials "$pi_user"

  if ! install_chromium_wrapper "$pi_user"; then
    err "Auto-load setup failed. You may need to load the extension manually once."
  fi

  log "Provisioning complete. Rebooting now..."
  reboot
}

main "$@"
