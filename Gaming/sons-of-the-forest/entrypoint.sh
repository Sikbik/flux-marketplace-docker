#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[sotf] %s\n' "$*"
}

is_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

json_bool() {
  if is_true "${1:-false}"; then
    printf 'true'
  else
    printf 'false'
  fi
}

json_number_or_default() {
  local value="${1:-}"
  local default_value="${2:-0}"

  if [[ "${value}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "${value}"
    return 0
  fi

  printf '%s' "${default_value}"
}

json_value_from_string() {
  local raw
  raw="$(trim "${1:-}")"

  if [[ -z "${raw}" ]]; then
    printf '""'
    return 0
  fi

  case "${raw,,}" in
    true) printf 'true'; return 0 ;;
    false) printf 'false'; return 0 ;;
  esac

  if [[ "${raw}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "${raw}"
    return 0
  fi

  printf '"%s"' "$(json_escape "${raw}")"
}

kv_to_json_object() {
  local input="${1:-}"
  input="${input//$'\r'/}"
  input="${input//,/$'\n'}"
  input="${input//;/$'\n'}"

  local obj="{"
  local first="true"
  local line key value
  while IFS= read -r line; do
    line="$(trim "${line}")"
    [[ -z "${line}" ]] && continue
    [[ "${line}" == \#* ]] && continue
    [[ "${line}" != *"="* ]] && continue

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ -z "${key}" ]] && continue

    if [[ "${first}" != "true" ]]; then
      obj+=","
    fi
    first="false"

    obj+="\"$(json_escape "${key}")\":$(json_value_from_string "${value}")"
  done <<< "${input}"
  obj+="}"
  printf '%s' "${obj}"
}

read_json_source() {
  local b64="${1:-}"
  local file_path="${2:-}"
  local raw_json="${3:-}"
  local kv_pairs="${4:-}"
  local fallback="${5:-{}}"

  if [[ -n "${b64}" ]]; then
    if ! printf '%s' "${b64}" | base64 -d 2>/dev/null; then
      log "ERROR: Failed to decode base64 JSON value."
      printf '%s' "${fallback}"
    fi
    return 0
  fi

  if [[ -n "${file_path}" ]]; then
    if [[ ! -f "${file_path}" ]]; then
      log "ERROR: JSON file not found: ${file_path}"
      printf '%s' "${fallback}"
      return 0
    fi
    cat "${file_path}"
    return 0
  fi

  if [[ -n "${raw_json}" ]]; then
    printf '%s' "${raw_json}"
    return 0
  fi

  if [[ -n "${kv_pairs}" ]]; then
    kv_to_json_object "${kv_pairs}"
    return 0
  fi

  printf '%s' "${fallback}"
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

  local required_gb="${MIN_FREE_GB:-30}"
  if [[ ! "${required_gb}" =~ ^[0-9]+$ ]]; then
    required_gb=30
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
    log "ERROR: Not enough free disk space to install/update Sons of the Forest."
    log "Install path: ${STEAM_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    log "Tip: Ensure ${STEAM_INSTALL_DIR} is on a mounted Flux volume (e.g. /data/server)."
    exit 1
  fi
}

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_APP_ID="${STEAM_APP_ID:-2465200}"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"

SOTF_USERDATA_PATH="${SOTF_USERDATA_PATH:-/config}"
CONFIG_FILE="${SOTF_CONFIG_FILE:-${SOTF_USERDATA_PATH}/dedicatedserver.cfg}"
OWNERS_FILE="${SOTF_OWNERS_FILE:-${SOTF_USERDATA_PATH}/ownerswhitelist.txt}"

WINEPREFIX="${WINEPREFIX:-/data/wine/prefix}"
WINEARCH="${WINEARCH:-win64}"
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

SOTF_PASSWORD="${SOTF_PASSWORD:-}"
if [[ -z "${SOTF_PASSWORD}" && -n "${SOTF_SERVER_PASSWORD:-}" ]]; then
  SOTF_PASSWORD="${SOTF_SERVER_PASSWORD}"
fi

SOTF_ADMINS_LIST="${SOTF_OWNERS:-}"
if [[ -z "${SOTF_ADMINS_LIST}" && -n "${SOTF_ADMINS:-}" ]]; then
  SOTF_ADMINS_LIST="${SOTF_ADMINS}"
fi

log "=========================================="
log "  Sons of the Forest Dedicated Server"
log "  (SteamCMD + Wine, Flux-friendly)"
log "=========================================="
log "Steam AppID: ${STEAM_APP_ID}"
log "Install dir: ${STEAM_INSTALL_DIR}"
log "User data:   ${SOTF_USERDATA_PATH}"
log "Config file: ${CONFIG_FILE}"
log "Admins file: ${OWNERS_FILE}"
log "Wine prefix: ${WINEPREFIX}"

run_as_steam() {
  gosu steam "$@"
}

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

mkdir -p "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ "${id_changed}" == "true" ]]; then
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  else
    chown steam:steam "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  fi
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}"; then
  chmod 700 "${STEAM_INSTALL_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
else
  chmod 755 "${STEAM_INSTALL_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
fi
chmod 755 "${SOTF_USERDATA_PATH}" >/dev/null 2>&1 || true

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

  local steamcmd_home="${STEAMCMD_HOME:-}"
  if [[ -z "${steamcmd_home}" ]]; then
    steamcmd_home="/data/steam"
  fi
  mkdir -p "${steamcmd_home}" >/dev/null 2>&1 || true

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

  log "Checking for server updates via SteamCMD..."

  local rc=0
  set +e
  run_as_steam env HOME="${steamcmd_home}" "${cmd[@]}"
  rc=$?
  set -e

  if (( rc == 0 )); then
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    log "SteamCMD failed (rc=${rc}); retrying once after recursive chown..."
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${steamcmd_home}" /home/steam 2>/dev/null || true
  else
    log "SteamCMD failed (rc=${rc}); retrying once..."
  fi

  set +e
  run_as_steam env HOME="${steamcmd_home}" "${cmd[@]}"
  rc=$?
  set -e

  return "${rc}"
}

steamcmd_update

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}" && [[ "$(id -u)" -eq 0 ]]; then
  log "HARDEN_FLUX_VOLUME_BROWSER=true; tightening permissions on /data/server and /data/wine..."
  chown steam:steam "${STEAM_INSTALL_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  chmod 700 "${STEAM_INSTALL_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
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
    xvfb_cmd+=(-screen 0 1024x768x16 -nolisten tcp -ac)
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

if is_true "${MANAGE_CONFIG:-true}"; then
  apply_mode="${SOTF_CONFIG_APPLY_MODE:-always}"
  if [[ "${apply_mode}" == "once" && -f "${CONFIG_FILE}" ]]; then
    log "Config exists and SOTF_CONFIG_APPLY_MODE=once; not overwriting ${CONFIG_FILE}."
  else
    log "Generating ${CONFIG_FILE} (MANAGE_CONFIG=true)..."

    ip="$(json_escape "${SOTF_IP_ADDRESS:-0.0.0.0}")"
    server_name="$(json_escape "${SOTF_SERVER_NAME:-RunOnFlux}")"
    password="$(json_escape "${SOTF_PASSWORD}")"

    game_settings_json="$(read_json_source "${SOTF_GAME_SETTINGS_JSON_B64:-}" "${SOTF_GAME_SETTINGS_JSON_FILE:-}" "${SOTF_GAME_SETTINGS_JSON:-}" "${SOTF_GAME_SETTINGS:-}" "{}")"
    custom_game_mode_settings_json="$(read_json_source "${SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON_B64:-}" "${SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON_FILE:-}" "${SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON:-}" "${SOTF_CUSTOM_GAME_MODE_SETTINGS:-}" "{}")"

    cat > "${CONFIG_FILE}" <<EOF
{
  "IpAddress": "${ip}",
  "GamePort": $(json_number_or_default "${SOTF_GAME_PORT:-8766}" "8766"),
  "QueryPort": $(json_number_or_default "${SOTF_QUERY_PORT:-27016}" "27016"),
  "BlobSyncPort": $(json_number_or_default "${SOTF_BLOB_SYNC_PORT:-9700}" "9700"),
  "ServerName": "${server_name}",
  "MaxPlayers": $(json_number_or_default "${SOTF_MAX_PLAYERS:-8}" "8"),
  "Password": "${password}",
  "LanOnly": $(json_bool "${SOTF_LAN_ONLY:-false}"),
  "SaveSlot": $(json_number_or_default "${SOTF_SAVE_SLOT:-1}" "1"),
  "SaveMode": "$(json_escape "${SOTF_SAVE_MODE:-Continue}")",
  "GameMode": "$(json_escape "${SOTF_GAME_MODE:-Normal}")",
  "SaveInterval": $(json_number_or_default "${SOTF_SAVE_INTERVAL:-600}" "600"),
  "IdleDayCycleSpeed": $(json_number_or_default "${SOTF_IDLE_DAY_CYCLE_SPEED:-0.0}" "0.0"),
  "IdleTargetFramerate": $(json_number_or_default "${SOTF_IDLE_TARGET_FRAMERATE:-5}" "5"),
  "ActiveTargetFramerate": $(json_number_or_default "${SOTF_ACTIVE_TARGET_FRAMERATE:-60}" "60"),
  "LogFilesEnabled": $(json_bool "${SOTF_LOG_FILES_ENABLED:-true}"),
  "TimestampLogFilenames": $(json_bool "${SOTF_TIMESTAMP_LOG_FILENAMES:-true}"),
  "TimestampLogEntries": $(json_bool "${SOTF_TIMESTAMP_LOG_ENTRIES:-true}"),
  "SkipNetworkAccessibilityTest": $(json_bool "${SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST:-true}"),
  "GameSettings": ${game_settings_json},
  "CustomGameModeSettings": ${custom_game_mode_settings_json}
}
EOF

    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${CONFIG_FILE}" >/dev/null 2>&1 || true
    fi
  fi
fi

if [[ ! -f "${OWNERS_FILE}" ]]; then
  cat > "${OWNERS_FILE}" <<'EOF'
# ownerswhitelist.txt
# Put one SteamID64 per line. Example:
# 76561198000000000
EOF
  if [[ "$(id -u)" -eq 0 ]]; then
    chown steam:steam "${OWNERS_FILE}" >/dev/null 2>&1 || true
  fi
fi

owners_apply_mode="${SOTF_OWNERS_APPLY_MODE:-always}"
if [[ -n "${SOTF_ADMINS_LIST:-}" ]]; then
  if [[ "${owners_apply_mode}" == "once" && -f "${OWNERS_FILE}" && -s "${OWNERS_FILE}" ]]; then
    log "Admins list exists and SOTF_OWNERS_APPLY_MODE=once; not overwriting ${OWNERS_FILE}."
  else
    log "Writing admins list from SOTF_OWNERS/SOTF_ADMINS..."
    {
      echo "# ownerswhitelist.txt (generated from SOTF_OWNERS/SOTF_ADMINS)"
      printf '%s' "${SOTF_ADMINS_LIST}" | tr ', ' '\n' | sed '/^$/d'
    } > "${OWNERS_FILE}"
    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${OWNERS_FILE}" >/dev/null 2>&1 || true
    fi
  fi
fi

SERVER_EXE="${SOTF_SERVER_EXE:-${STEAM_INSTALL_DIR}/SonsOfTheForestDS.exe}"
if [[ ! -f "${SERVER_EXE}" ]]; then
  log "ERROR: Server EXE not found at ${SERVER_EXE}"
  log "Contents of install dir:"
  ls -la "${STEAM_INSTALL_DIR}" || true
  exit 1
fi

log "Launching server..."
log "Args: -batchmode -nographics -userdatapath ${SOTF_USERDATA_PATH} ${SOTF_SERVER_ARGS:-}"

WINE_BIN="wine64"
if ! command -v "${WINE_BIN}" >/dev/null 2>&1; then
  WINE_BIN="wine"
fi

cd "${STEAM_INSTALL_DIR}"
exec gosu steam env \
  DISPLAY="${DISPLAY}" \
  WINEPREFIX="${WINEPREFIX}" \
  WINEARCH="${WINEARCH}" \
  WINEDEBUG="${WINEDEBUG:-}" \
  WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
  "${WINE_BIN}" "${SERVER_EXE}" \
    -batchmode \
    -nographics \
    -userdatapath "${SOTF_USERDATA_PATH}" \
    ${SOTF_SERVER_ARGS:-}
