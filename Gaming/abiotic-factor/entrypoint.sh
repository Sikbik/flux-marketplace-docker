#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[abiotic] %s\n' "$*"
}

log_err() {
  printf '[abiotic] %s\n' "$*" >&2
}

mask_server_args_for_log() {
  local out=()
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -ServerPassword=*) out+=("-ServerPassword=<redacted>") ;;
      -AdminPassword=*) out+=("-AdminPassword=<redacted>") ;;
      *) out+=("${arg}") ;;
    esac
  done
  printf '%s' "${out[*]}"
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

  local required_gb="${MIN_FREE_GB:-20}"
  if [[ ! "${required_gb}" =~ ^[0-9]+$ ]]; then
    required_gb=20
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
    log "ERROR: Not enough free disk space to install/update Abiotic Factor."
    log "Install path: ${STEAM_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    log "Tip: Ensure ${STEAM_INSTALL_DIR} is on a mounted Flux volume (e.g. /data/server)."
    exit 1
  fi
}

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_APP_ID="${STEAM_APP_ID:-2857200}"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"

AF_SAVED_DIR="${AF_SAVED_DIR:-/config/Saved}"

WINEPREFIX="${WINEPREFIX:-/opt/wine/prefix}"
WINEARCH="${WINEARCH:-win64}"
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

log "=========================================="
log "  Abiotic Factor Dedicated Server"
log "  (SteamCMD + Wine, Flux-friendly)"
log "=========================================="
log "Steam AppID: ${STEAM_APP_ID}"
log "Install dir: ${STEAM_INSTALL_DIR}"
log "Saved dir:   ${AF_SAVED_DIR}"
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

mkdir -p "${STEAM_INSTALL_DIR}" "${AF_SAVED_DIR}" "$(dirname "${WINEPREFIX}")"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ "${id_changed}" == "true" ]]; then
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${AF_SAVED_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  else
    chown steam:steam "${STEAM_INSTALL_DIR}" "${AF_SAVED_DIR}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  fi
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}"; then
  chmod 700 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
  if [[ "$(dirname "${WINEPREFIX}")" == /data/* ]]; then
    chmod 700 "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  fi
else
  chmod 755 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
  chmod 755 "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
fi
chmod 755 "$(dirname "${AF_SAVED_DIR}")" "${AF_SAVED_DIR}" >/dev/null 2>&1 || true

maybe_lockdown_unused_data_wine_dir() {
  if ! is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}"; then
    return 0
  fi
  [[ "$(id -u)" -eq 0 ]] || return 0

  case "${WINEPREFIX}" in
    /data/wine/*) return 0 ;;
  esac

  if [[ -d "/data/wine" ]]; then
    log "HARDEN_FLUX_VOLUME_BROWSER=true; locking down unused /data/wine to reduce Flux volume explorer load."
    chown root:root "/data/wine" >/dev/null 2>&1 || true
    chmod 700 "/data/wine" >/dev/null 2>&1 || true
  fi
}

maybe_lockdown_unused_data_wine_dir

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

    log "SteamCMD: updating app ${STEAM_APP_ID} (validate=${STEAMCMD_VALIDATE:-true})..."
    log "SteamCMD log: ${steamcmd_log}"
    : > "${steamcmd_log}" || true

    if ! run_as_steam env HOME="${steamcmd_home}" "${cmd[@]}" > "${steamcmd_log}" 2>&1; then
      if grep -qi "Missing configuration" "${steamcmd_log}" 2>/dev/null; then
        steamcmd_error_kind="missing_config"
      fi
      return 1
    fi

    return 0
  }

  if run_steamcmd; then
    return 0
  fi

  if [[ "${steamcmd_error_kind}" == "missing_config" ]] && is_true "${STEAMCMD_RESET_ON_MISSING_CONFIG:-true}"; then
    log "SteamCMD reported missing configuration; resetting Steam state and retrying once..."
    rm -rf "${steamcmd_home}/Steam/config" "${steamcmd_home}/Steam/appcache" >/dev/null 2>&1 || true
    if run_steamcmd; then
      return 0
    fi
  fi

  if is_true "${STEAMCMD_VALIDATE:-true}" && is_true "${STEAMCMD_RETRY_NO_VALIDATE_ON_FAIL:-true}"; then
    log "SteamCMD failed with validate enabled; retrying once with STEAMCMD_VALIDATE=false..."
    STEAMCMD_VALIDATE=false run_steamcmd && return 0
  fi

  log "SteamCMD failed. See ${steamcmd_log} and ${steamcmd_home}/Steam/logs for details."
  if [[ -f "${steamcmd_log}" ]]; then
    log "SteamCMD output (tail):"
    tail -n 120 "${steamcmd_log}" 2>/dev/null || true
  fi
  log "Steam logs (tail):"
  tail -n 80 "${steamcmd_home}/Steam/logs/stderr.txt" 2>/dev/null || true
  tail -n 80 "${steamcmd_home}/Steam/logs/bootstrap_log.txt" 2>/dev/null || true

  return 1
}

steamcmd_update

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-false}" && [[ "$(id -u)" -eq 0 ]]; then
  log "HARDEN_FLUX_VOLUME_BROWSER=true; tightening permissions on /data/server and /data/steam..."
  chown steam:steam "${STEAM_INSTALL_DIR}" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
  chmod 700 "${STEAM_INSTALL_DIR}" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
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

detect_server_exe() {
  for candidate in \
    "${STEAM_INSTALL_DIR}/AbioticFactor/Binaries/Win64/AbioticFactorServer-Win64-Shipping.exe" \
    "${STEAM_INSTALL_DIR}/AbioticFactor/Binaries/Win64/AbioticFactorServer.exe" \
    "${STEAM_INSTALL_DIR}/AbioticFactorServer.exe"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_server_exe() {
  if [[ -n "${AF_SERVER_EXE:-}" ]]; then
    printf '%s\n' "${AF_SERVER_EXE}"
    return 0
  fi

  local found=""
  found="$(detect_server_exe 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    printf '%s\n' "${found}"
    return 0
  fi

  printf '%s\n' "${STEAM_INSTALL_DIR}/AbioticFactor/Binaries/Win64/AbioticFactorServer-Win64-Shipping.exe"
}

SERVER_EXE="$(resolve_server_exe)"
if [[ ! -f "${SERVER_EXE}" ]]; then
  log "ERROR: Server EXE not found at ${SERVER_EXE}"
  log "Contents of install dir:"
  ls -la "${STEAM_INSTALL_DIR}" || true
  exit 1
fi

server_exe_dir="$(dirname "${SERVER_EXE}")"

AF_GAME_DIR="${AF_GAME_DIR:-${STEAM_INSTALL_DIR}/AbioticFactor}"
if [[ ! -d "${AF_GAME_DIR}" ]]; then
  maybe_game_dir="$(readlink -f "${server_exe_dir}/../.." 2>/dev/null || true)"
  if [[ -n "${maybe_game_dir}" && -d "${maybe_game_dir}" ]]; then
    AF_GAME_DIR="${maybe_game_dir}"
  fi
fi

ensure_saved_symlink() {
  local persisted="${AF_SAVED_DIR}"
  local link_path="${AF_GAME_DIR}/Saved"

  mkdir -p "${persisted}" >/dev/null 2>&1 || true

  if [[ -L "${link_path}" ]]; then
    return 0
  fi

  if [[ -e "${link_path}" ]]; then
    mkdir -p "${persisted}" >/dev/null 2>&1 || true
    log "Migrating existing Saved data into ${persisted} (best-effort)..."
    cp -a -n "${link_path}/." "${persisted}/" >/dev/null 2>&1 || cp -a "${link_path}/." "${persisted}/" >/dev/null 2>&1 || true
    rm -rf "${link_path}" >/dev/null 2>&1 || true
  fi

  ln -s "${persisted}" "${link_path}"
}

ensure_saved_symlink

if [[ "$(id -u)" -eq 0 ]]; then
  chown -R steam:steam "${AF_SAVED_DIR}" >/dev/null 2>&1 || true
fi

write_admin_ini_if_needed() {
  if ! is_true "${MANAGE_CONFIG:-true}"; then
    return 0
  fi

  local mods_raw
  mods_raw="$(trim "${AF_MODERATORS:-}")"
  [[ -z "${mods_raw}" ]] && return 0

  local apply_mode="${AF_MODERATORS_APPLY_MODE:-always}"
  local rel="${AF_ADMIN_INI_RELATIVE_PATH:-SaveGames/Server/Admin.ini}"
  local path="${AF_SAVED_DIR}/${rel}"
  mkdir -p "$(dirname "${path}")" >/dev/null 2>&1 || true

  if [[ "${apply_mode}" == "once" && -f "${path}" && -s "${path}" ]]; then
    log "Admin.ini exists and AF_MODERATORS_APPLY_MODE=once; not overwriting ${path}."
    return 0
  fi

  log "Writing moderators list to ${path}..."
  {
    echo "[Moderators]"
    printf '%s' "${mods_raw}" | tr ', ' '\n' | sed '/^$/d' | while IFS= read -r id; do
      id="$(trim "${id}")"
      [[ -z "${id}" ]] && continue
      echo "Moderator=${id}"
    done
  } > "${path}"

  if [[ "$(id -u)" -eq 0 ]]; then
    chown steam:steam "${path}" >/dev/null 2>&1 || true
  fi
}

write_sandbox_ini_if_needed() {
  if ! is_true "${MANAGE_CONFIG:-true}"; then
    return 0
  fi

  local apply_mode="${AF_SANDBOX_APPLY_MODE:-once}"
  local rel="${AF_SANDBOX_INI_RELATIVE_PATH:-Config/WindowsServer/ServerSandbox.ini}"
  local path="${AF_SAVED_DIR}/${rel}"

  local src_b64="${AF_SANDBOX_SETTINGS_INI_B64:-}"
  local src_file="${AF_SANDBOX_SETTINGS_INI_FILE:-}"
  local src_raw="${AF_SANDBOX_SETTINGS_INI:-}"

  if [[ -z "$(trim "${src_b64}${src_file}${src_raw}")" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${path}")" >/dev/null 2>&1 || true

  if [[ "${apply_mode}" == "once" && -f "${path}" && -s "${path}" ]]; then
    log "Sandbox ini exists and AF_SANDBOX_APPLY_MODE=once; not overwriting ${path}."
    return 0
  fi

  log "Writing sandbox ini to ${path}..."
  if [[ -n "${src_b64}" ]]; then
    if ! printf '%s' "${src_b64}" | base64 -d > "${path}" 2>/dev/null; then
      log_err "ERROR: Failed to decode AF_SANDBOX_SETTINGS_INI_B64."
      return 1
    fi
  elif [[ -n "${src_file}" ]]; then
    if [[ ! -f "${src_file}" ]]; then
      log_err "ERROR: AF_SANDBOX_SETTINGS_INI_FILE not found: ${src_file}"
      return 1
    fi
    cat "${src_file}" > "${path}"
  else
    printf '%s\n' "${src_raw}" > "${path}"
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    chown steam:steam "${path}" >/dev/null 2>&1 || true
  fi
}

write_admin_ini_if_needed
write_sandbox_ini_if_needed

log "Launching server..."

AF_BASE_GAME_APP_ID="${AF_BASE_GAME_APP_ID:-427410}"
AF_STEAM_GAME_ID="${AF_STEAM_GAME_ID:-${AF_BASE_GAME_APP_ID}}"

if is_true "${AF_WRITE_STEAM_APPID_TXT:-true}"; then
  log "Ensuring steam_appid.txt exists (${AF_BASE_GAME_APP_ID})..."
  printf '%s' "${AF_BASE_GAME_APP_ID}" > "${server_exe_dir}/steam_appid.txt"
  if [[ "$(id -u)" -eq 0 ]]; then
    chown steam:steam "${server_exe_dir}/steam_appid.txt" >/dev/null 2>&1 || true
  fi
fi

AF_SERVER_NAME="${AF_SERVER_NAME:-RunOnFlux - Abiotic Factor}"
AF_SERVER_PASSWORD="${AF_SERVER_PASSWORD:-}"
AF_ADMIN_PASSWORD="${AF_ADMIN_PASSWORD:-}"
AF_MAX_PLAYERS="${AF_MAX_PLAYERS:-6}"
AF_PORT="${AF_PORT:-7777}"
AF_QUERY_PORT="${AF_QUERY_PORT:-27015}"
AF_WORLD_SAVE_NAME="${AF_WORLD_SAVE_NAME:-Cascade}"

server_args=()
server_args+=(-log)
server_args+=("-SteamServerName=${AF_SERVER_NAME}")
server_args+=("-MaxServerPlayers=${AF_MAX_PLAYERS}")
server_args+=("-PORT=${AF_PORT}")
server_args+=("-QueryPort=${AF_QUERY_PORT}")
server_args+=("-WorldSaveName=${AF_WORLD_SAVE_NAME}")

if [[ -n "${AF_SERVER_PASSWORD}" ]]; then
  server_args+=("-ServerPassword=${AF_SERVER_PASSWORD}")
fi

if [[ -n "${AF_ADMIN_PASSWORD}" ]]; then
  server_args+=("-AdminPassword=${AF_ADMIN_PASSWORD}")
fi

if is_true "${MANAGE_CONFIG:-true}" && [[ -n "$(trim "${AF_MODERATORS:-}")" ]]; then
  server_args+=("-AdminIniPath=${AF_ADMIN_INI_RELATIVE_PATH:-SaveGames/Server/Admin.ini}")
fi

if is_true "${MANAGE_CONFIG:-true}" && [[ -n "$(trim "${AF_SANDBOX_SETTINGS_INI_B64}${AF_SANDBOX_SETTINGS_INI_FILE}${AF_SANDBOX_SETTINGS_INI}")" ]]; then
  server_args+=("-SandboxIniPath=${AF_SANDBOX_INI_RELATIVE_PATH:-Config/WindowsServer/ServerSandbox.ini}")
fi

log "Args: $(mask_server_args_for_log "${server_args[@]}")"
if [[ -n "${AF_SERVER_ARGS:-}" ]]; then
  log "Extra args: set (not printed to avoid leaking secrets)"
fi

WINE_BIN="wine64"
if ! command -v "${WINE_BIN}" >/dev/null 2>&1; then
  WINE_BIN="wine"
fi

cd "${server_exe_dir}"
exec gosu steam env \
  DISPLAY="${DISPLAY}" \
  WINEPREFIX="${WINEPREFIX}" \
  WINEARCH="${WINEARCH}" \
  WINEDEBUG="${WINEDEBUG:-}" \
  WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
  SteamAppId="${AF_BASE_GAME_APP_ID}" \
  SteamGameId="${AF_STEAM_GAME_ID}" \
  "${WINE_BIN}" "${SERVER_EXE}" \
    "${server_args[@]}" \
    ${AF_SERVER_ARGS:-}
