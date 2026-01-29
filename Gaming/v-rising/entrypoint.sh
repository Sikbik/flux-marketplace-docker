#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[vrising] %s\n' "$*"
}

log_err() {
  printf '[vrising] %s\n' "$*" >&2
}

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

bytes_available_on_path() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    path="$(dirname "${path}")"
  fi
  df -PB1 "${path}" 2>/dev/null | awk 'NR==2 {print $4}'
}

mountpoint_for_path() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    path="$(dirname "${path}")"
  fi
  df -P "${path}" 2>/dev/null | awk 'NR==2 {print $6}'
}

disk_preflight() {
  if ! is_true "${DISK_PREFLIGHT:-true}"; then
    return 0
  fi

  local required_gb="${MIN_FREE_GB:-15}"
  if [[ ! "${required_gb}" =~ ^[0-9]+$ ]]; then
    required_gb=15
  fi
  local required_bytes=$((required_gb * 1024 * 1024 * 1024))

  local avail_bytes
  avail_bytes="$(bytes_available_on_path "${STEAM_INSTALL_DIR}")"
  if [[ -z "${avail_bytes}" ]]; then
    log "Disk preflight: unable to determine free space for ${STEAM_INSTALL_DIR} (skipping)"
    return 0
  fi

  local avail_gb=$((avail_bytes / 1024 / 1024 / 1024))
  local mountpoint
  mountpoint="$(mountpoint_for_path "${STEAM_INSTALL_DIR}")"

  if (( avail_bytes < required_bytes )); then
    log_err "ERROR: Not enough free disk space to install/update V Rising."
    log_err "Install path: ${STEAM_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log_err "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log_err "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    exit 1
  fi
}

mask_args_for_log() {
  local in=("$@")
  local out=()
  local i=0
  while (( i < ${#in[@]} )); do
    local arg="${in[i]}"
    case "${arg}" in
      -password|--password)
        out+=("${arg}" "<redacted>")
        i=$((i + 2))
        ;;
      *password*|*Password*)
        out+=("<redacted>")
        i=$((i + 1))
        ;;
      *)
        out+=("${arg}")
        i=$((i + 1))
        ;;
    esac
  done
  printf '%s' "${out[*]}"
}

split_list_to_lines() {
  # Converts commas/spaces into newline-separated tokens; removes empties.
  tr ', ' '\n\n' | awk 'NF {print $0}'
}

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_APP_ID="${STEAM_APP_ID:-1829350}"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"

VR_PERSISTENT_DATA_DIR="${VR_PERSISTENT_DATA_DIR:-/config/save-data}"
VR_SETTINGS_DIR="${VR_PERSISTENT_DATA_DIR}/Settings"

WINEPREFIX="${WINEPREFIX:-/opt/wine/prefix}"
WINEARCH="${WINEARCH:-win64}"
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

run_as_steam() {
  gosu steam "$@"
}

log "=========================================="
log "  V Rising Dedicated Server"
log "  (SteamCMD + Wine, Flux-friendly)"
log "=========================================="
log "Steam AppID:        ${STEAM_APP_ID}"
log "Install dir:        ${STEAM_INSTALL_DIR}"
log "Persistent dir:     ${VR_PERSISTENT_DATA_DIR}"
log "Wine prefix:        ${WINEPREFIX}"
log "Game/Query ports:   ${VR_GAME_PORT:-9876}/${VR_QUERY_PORT:-9877}"

id_changed="false"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "${PUID:-}" ]] && [[ "${PUID}" != "1000" ]]; then
    log "Updating UID to ${PUID}..."
    if usermod -u "${PUID}" steam; then
      id_changed="true"
    fi
  fi

  if [[ -n "${PGID:-}" ]] && [[ "${PGID}" != "1000" ]]; then
    log "Updating GID to ${PGID}..."
    if groupmod -g "${PGID}" steam; then
      id_changed="true"
    fi
  fi
else
  if [[ -n "${PUID:-}" || -n "${PGID:-}" ]]; then
    log "Warning: PUID/PGID set but container is not running as root; skipping user/group modifications."
  fi
fi

mkdir -p "${STEAM_INSTALL_DIR}" "${VR_SETTINGS_DIR}" "$(dirname "${WINEPREFIX}")"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ "${id_changed}" == "true" ]]; then
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${VR_PERSISTENT_DATA_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  else
    chown steam:steam "${STEAM_INSTALL_DIR}" "${VR_PERSISTENT_DATA_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  fi
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}"; then
  chmod 700 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
else
  chmod 755 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
fi
chmod 755 "$(dirname "${VR_PERSISTENT_DATA_DIR}")" "${VR_PERSISTENT_DATA_DIR}" "${VR_SETTINGS_DIR}" >/dev/null 2>&1 || true

mkdir -p "${WINEPREFIX}"
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R steam:steam "${WINEPREFIX}" >/dev/null 2>&1 || true
fi

disk_preflight

steamcmd_update() {
  if ! is_true "${AUTO_UPDATE:-true}"; then
    log "AUTO_UPDATE=false; skipping SteamCMD update."
    return 0
  fi

  local steamcmd_home="${STEAMCMD_HOME:-/data/steam}"
  mkdir -p "${steamcmd_home}" >/dev/null 2>&1 || true

  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R steam:steam "${steamcmd_home}" >/dev/null 2>&1 || true
    if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}"; then
      chmod 700 "${steamcmd_home}" >/dev/null 2>&1 || true
    else
      chmod 755 "${steamcmd_home}" >/dev/null 2>&1 || true
    fi
  fi

  local steamcmd_log="${STEAMCMD_LOG_FILE:-${steamcmd_home}/steamcmd.log}"
  local steamcmd_error_kind=""

  run_steamcmd() {
    steamcmd_error_kind=""

    local -a cmd
    cmd=("${STEAMCMD}" +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1)

    if [[ -n "${STEAMCMD_FORCE_PLATFORM_TYPE:-windows}" ]]; then
      cmd+=(+@sSteamCmdForcePlatformType "${STEAMCMD_FORCE_PLATFORM_TYPE:-windows}")
    fi

    cmd+=(+force_install_dir "${STEAM_INSTALL_DIR}")

    if [[ "${STEAM_LOGIN:-anonymous}" == "anonymous" ]]; then
      cmd+=(+login anonymous)
    else
      cmd+=(+login "${STEAM_LOGIN}" "${STEAM_PASSWORD:-}" "${STEAM_GUARD:-}")
    fi

    cmd+=(+app_update "${STEAM_APP_ID}")

    if [[ -n "${STEAM_BRANCH:-}" ]]; then
      cmd+=(-beta "${STEAM_BRANCH}")
    fi
    if [[ -n "${STEAM_BRANCH_PASSWORD:-}" ]]; then
      cmd+=(-betapassword "${STEAM_BRANCH_PASSWORD}")
    fi
    if is_true "${STEAMCMD_VALIDATE:-true}"; then
      cmd+=(validate)
    fi

    if [[ -n "${STEAMCMD_EXTRA_ARGS:-}" ]]; then
      # shellcheck disable=SC2206
      cmd+=(${STEAMCMD_EXTRA_ARGS})
    fi

    cmd+=(+quit)

    rm -f "${steamcmd_log}" >/dev/null 2>&1 || true

    local rc=0
    set +e
    run_as_steam env HOME="${steamcmd_home}" "${cmd[@]}" 2>&1 | tee "${steamcmd_log}"
    rc="${PIPESTATUS[0]}"
    set -e

    if [[ -f "${steamcmd_log}" ]]; then
      if grep -q "Missing configuration" "${steamcmd_log}" 2>/dev/null; then
        steamcmd_error_kind="missing_configuration"
      elif grep -q "Missing file permissions" "${steamcmd_log}" 2>/dev/null; then
        steamcmd_error_kind="missing_file_permissions"
      elif grep -q "Disk write failure" "${steamcmd_log}" 2>/dev/null; then
        steamcmd_error_kind="disk_write_failure"
      fi
    fi

    return "${rc}"
  }

  log "Checking for server updates via SteamCMD..."

  run_steamcmd
  local rc=$?
  if (( rc == 0 )); then
    return 0
  fi

  if [[ "${steamcmd_error_kind}" == "missing_file_permissions" ]] && [[ "$(id -u)" -eq 0 ]]; then
    log "SteamCMD returned Missing file permissions; fixing ownership and retrying once..."
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${steamcmd_home}" >/dev/null 2>&1 || true
    run_steamcmd
    rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  if [[ "${steamcmd_error_kind}" == "missing_configuration" ]] && is_true "${STEAMCMD_RESET_ON_MISSING_CONFIG:-true}"; then
    log "SteamCMD returned Missing configuration; wiping ${steamcmd_home}/Steam/config and retrying once..."
    rm -rf "${steamcmd_home}/Steam/config" "${steamcmd_home}/Steam/appcache" >/dev/null 2>&1 || true
    run_steamcmd
    rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  if is_true "${STEAMCMD_VALIDATE:-true}" && is_true "${STEAMCMD_RETRY_NO_VALIDATE_ON_FAIL:-true}"; then
    log "SteamCMD failed with validate enabled; retrying once with STEAMCMD_VALIDATE=false..."
    STEAMCMD_VALIDATE=false run_steamcmd
    rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  log_err "SteamCMD failed (rc=${rc}). See ${steamcmd_log} and ${steamcmd_home}/Steam/logs for details."
  return "${rc}"
}

steamcmd_update

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}" && [[ "$(id -u)" -eq 0 ]]; then
  log "HARDEN_FLUX_VOLUME_BROWSER=true; tightening permissions on /data/server and /data/steam..."
  chown steam:steam "${STEAM_INSTALL_DIR}" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
  chmod 700 "${STEAM_INSTALL_DIR}" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
fi

server_exe="$(find "${STEAM_INSTALL_DIR}" -maxdepth 5 -type f -iname 'VRisingServer.exe' -print -quit 2>/dev/null || true)"
if [[ -z "${server_exe}" ]]; then
  log_err "ERROR: Could not locate VRisingServer.exe under ${STEAM_INSTALL_DIR}."
  exit 1
fi
server_dir="$(dirname "${server_exe}")"

if is_true "${VR_WRITE_STEAM_APPID_TXT:-true}"; then
  if [[ "${VR_BASE_GAME_APP_ID:-1604030}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${VR_BASE_GAME_APP_ID}" >"${server_dir}/steam_appid.txt" || true
    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${server_dir}/steam_appid.txt" >/dev/null 2>&1 || true
    fi
  fi
fi

default_host_settings="$(find "${STEAM_INSTALL_DIR}" -type f -iname 'ServerHostSettings.json' -path '*StreamingAssets*' -print -quit 2>/dev/null || true)"
default_game_settings="$(find "${STEAM_INSTALL_DIR}" -type f -iname 'ServerGameSettings.json' -path '*StreamingAssets*' -print -quit 2>/dev/null || true)"

apply_host_settings() {
  python3 - "${1}" <<'PY'
import json, os, sys

path = sys.argv[1]
# Some vendor-provided JSON files include a UTF-8 BOM; use utf-8-sig so json can parse it.
with open(path, "r", encoding="utf-8-sig") as f:
    data = json.load(f)

def parse_int(s, default):
    try:
        return int(str(s).strip())
    except Exception:
        return default

def parse_bool(s, default):
    if s is None:
        return default
    s = str(s).strip().lower()
    if s == "":
        return default
    return s in ("1", "true", "yes", "y", "on")

data["Name"] = os.environ.get("VR_SERVER_NAME", data.get("Name", "RunOnFlux - V Rising"))
data["Description"] = os.environ.get("VR_SERVER_DESCRIPTION", data.get("Description", "")) or ""
data["Port"] = parse_int(os.environ.get("VR_GAME_PORT"), data.get("Port", 9876))
data["QueryPort"] = parse_int(os.environ.get("VR_QUERY_PORT"), data.get("QueryPort", 9877))
data["MaxConnectedUsers"] = parse_int(os.environ.get("VR_MAX_PLAYERS"), data.get("MaxConnectedUsers", 40))
data["MaxConnectedAdmins"] = parse_int(os.environ.get("VR_MAX_ADMINS"), data.get("MaxConnectedAdmins", 4))
data["ServerFps"] = parse_int(os.environ.get("VR_SERVER_FPS"), data.get("ServerFps", 30))
data["SaveName"] = os.environ.get("VR_SAVE_NAME", data.get("SaveName", "RunOnFlux"))
data["Password"] = os.environ.get("VR_PASSWORD", data.get("Password", "")) or ""
data["Secure"] = parse_bool(os.environ.get("VR_SECURE"), data.get("Secure", True))

# Listing flags vary by server version; write all common keys.
list_on_steam = parse_bool(os.environ.get("VR_LIST_ON_STEAM"), data.get("ListOnSteam", True))
list_on_eos = parse_bool(os.environ.get("VR_LIST_ON_EOS"), data.get("ListOnEOS", True))
data["ListOnSteam"] = list_on_steam
data["ListOnEOS"] = list_on_eos
data["ListOnMasterServer"] = bool(list_on_steam or list_on_eos)

data["AutoSaveInterval"] = parse_int(os.environ.get("VR_AUTOSAVE_INTERVAL"), data.get("AutoSaveInterval", 600))
data["AutoSaveCount"] = parse_int(os.environ.get("VR_AUTOSAVE_COUNT"), data.get("AutoSaveCount", 50))

preset = (os.environ.get("VR_GAME_SETTINGS_PRESET") or "").strip()
if preset:
    data["GameSettingsPreset"] = preset

rcon = data.get("Rcon") or {}
rcon["Enabled"] = parse_bool(os.environ.get("VR_RCON_ENABLED"), rcon.get("Enabled", False))
rcon["Port"] = parse_int(os.environ.get("VR_RCON_PORT"), rcon.get("Port", 25575))
rcon["Password"] = (os.environ.get("VR_RCON_PASSWORD") or rcon.get("Password") or "")
data["Rcon"] = rcon

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, path)
PY
}

if is_true "${MANAGE_CONFIG:-true}"; then
  mkdir -p "${VR_SETTINGS_DIR}"

  host_path="${VR_SETTINGS_DIR}/ServerHostSettings.json"
  game_path="${VR_SETTINGS_DIR}/ServerGameSettings.json"

  if [[ "${VR_CONFIG_APPLY_MODE:-always}" == "once" && -f "${host_path}" ]]; then
    log "ServerHostSettings.json exists and VR_CONFIG_APPLY_MODE=once; not overwriting."
  else
    if [[ -n "${default_host_settings}" && -f "${default_host_settings}" ]]; then
      cp -f "${default_host_settings}" "${host_path}"
    else
      cat >"${host_path}" <<EOF
{
  "Name": "RunOnFlux - V Rising",
  "Description": "",
  "Port": 9876,
  "QueryPort": 9877,
  "MaxConnectedUsers": 40,
  "MaxConnectedAdmins": 4,
  "ServerFps": 30,
  "SaveName": "RunOnFlux",
  "Password": "",
  "Secure": true,
  "ListOnSteam": true,
  "ListOnEOS": true,
  "ListOnMasterServer": true,
  "AutoSaveInterval": 600,
  "AutoSaveCount": 50,
  "Rcon": {
    "Enabled": false,
    "Port": 25575,
    "Password": ""
  }
}
EOF
    fi
    apply_host_settings "${host_path}"
    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${host_path}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${VR_CONFIG_APPLY_MODE:-always}" == "once" && -f "${game_path}" ]]; then
    log "ServerGameSettings.json exists and VR_CONFIG_APPLY_MODE=once; not overwriting."
  else
    if [[ -n "${VR_GAME_SETTINGS_JSON_B64:-}" ]]; then
      python3 - "${game_path}" <<'PY'
import base64, json, os, sys
out = sys.argv[1]
raw = base64.b64decode(os.environ["VR_GAME_SETTINGS_JSON_B64"]).decode("utf-8")
data = json.loads(raw)
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    elif [[ -n "${VR_GAME_SETTINGS_JSON:-}" ]]; then
      python3 - "${game_path}" <<'PY'
import json, os, sys
out = sys.argv[1]
data = json.loads(os.environ["VR_GAME_SETTINGS_JSON"])
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    elif [[ -n "${default_game_settings}" && -f "${default_game_settings}" ]]; then
      cp -f "${default_game_settings}" "${game_path}"
    else
      echo '{}' > "${game_path}"
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${game_path}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${VR_LISTS_APPLY_MODE:-always}" != "never" ]]; then
    if [[ -n "${VR_ADMIN_LIST:-}" ]]; then
      printf '%s\n' "${VR_ADMIN_LIST}" | split_list_to_lines > "${VR_SETTINGS_DIR}/adminlist.txt"
    fi
    if [[ -n "${VR_WHITELIST:-}" ]]; then
      printf '%s\n' "${VR_WHITELIST}" | split_list_to_lines > "${VR_SETTINGS_DIR}/whitelist.txt"
    fi
    if [[ -n "${VR_BANLIST:-}" ]]; then
      printf '%s\n' "${VR_BANLIST}" | split_list_to_lines > "${VR_SETTINGS_DIR}/banlist.txt"
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
      chown -R steam:steam "${VR_SETTINGS_DIR}" >/dev/null 2>&1 || true
    fi
  fi
fi

XVFB_DISPLAY="${XVFB_DISPLAY:-99}"
export DISPLAY=":${XVFB_DISPLAY}"

if is_true "${USE_XVFB:-true}"; then
  log "Starting virtual display (Xvfb) on ${DISPLAY}..."
  rm -f "/tmp/.X${XVFB_DISPLAY}-lock" "/tmp/.X11-unix/X${XVFB_DISPLAY}" 2>/dev/null || true

  xvfb_cmd=(Xvfb "${DISPLAY}")
  if [[ -n "${XVFB_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    xvfb_cmd+=(${XVFB_ARGS})
  else
    xvfb_cmd+=(-screen 0 1024x768x24 -nolisten tcp -ac)
  fi

  "${xvfb_cmd[@]}" &
  sleep 2
fi

if [[ ! -d "${WINEPREFIX}/drive_c" ]]; then
  log "Initializing Wine prefix (first boot; may take a few minutes)..."
  run_as_steam env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES}" wineboot -u 2>&1 || true
  sleep 5
  log "Wine prefix initialized."
fi

persistent_win_path="$(run_as_steam winepath -w "${VR_PERSISTENT_DATA_DIR}" 2>/dev/null || true)"
if [[ -z "${persistent_win_path}" ]]; then
  persistent_win_path="Z:\\config\\save-data"
fi

log_file="${VR_LOG_FILE:-}"
log_file_arg=()
if [[ -n "${log_file}" ]]; then
  if [[ "${log_file}" == /* ]]; then
    log_file="$(run_as_steam winepath -w "${log_file}" 2>/dev/null || echo "${log_file}")"
  fi
  log_file_arg=(-logFile "${log_file}")
fi

cmd=(
  wine
  "${server_exe}"
  -persistentDataPath "${persistent_win_path}"
  "${log_file_arg[@]}"
)

if [[ -n "${VR_SERVER_ARGS:-}" ]]; then
  read -r -a extra_split <<<"${VR_SERVER_ARGS}"
  cmd+=("${extra_split[@]}")
fi

log "Starting server..."
log "Args: $(mask_args_for_log "${cmd[@]}")"

cd "${server_dir}"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu steam "${cmd[@]}"
else
  exec "${cmd[@]}"
fi
