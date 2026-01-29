#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[valheim] %s\n' "$*"
}

log_err() {
  printf '[valheim] %s\n' "$*" >&2
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

  local required_gb="${MIN_FREE_GB:-5}"
  if [[ ! "${required_gb}" =~ ^[0-9]+$ ]]; then
    required_gb=5
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
    log_err "ERROR: Not enough free disk space to install/update Valheim."
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
      -password)
        out+=("-password" "<redacted>")
        i=$((i + 2))
        ;;
      -password=*)
        out+=("-password=<redacted>")
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

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_APP_ID="${STEAM_APP_ID:-896660}"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"

VALHEIM_SAVEDIR="${VALHEIM_SAVEDIR:-/config}"
VALHEIM_PORT="${VALHEIM_PORT:-2456}"
VALHEIM_STEAM_APP_ID="${VALHEIM_STEAM_APP_ID:-892970}"

log "=========================================="
log "  Valheim Dedicated Server"
log "  (SteamCMD, Flux-friendly)"
log "=========================================="
log "Steam AppID: ${STEAM_APP_ID}"
log "Install dir: ${STEAM_INSTALL_DIR}"
log "Save dir:    ${VALHEIM_SAVEDIR}"
log "Port:        ${VALHEIM_PORT}/udp (+1,+2)"

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

mkdir -p "${STEAM_INSTALL_DIR}" "${VALHEIM_SAVEDIR}" "${STEAMCMD_HOME:-/data/steam}"
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R steam:steam "${STEAM_INSTALL_DIR}" "${VALHEIM_SAVEDIR}" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-true}"; then
  chmod 700 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
else
  chmod 755 "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true
fi
chmod 755 "${VALHEIM_SAVEDIR}" >/dev/null 2>&1 || true

disk_preflight

steamcmd_update() {
  if ! is_true "${AUTO_UPDATE:-true}"; then
    log "AUTO_UPDATE=false; skipping SteamCMD update."
    return 0
  fi

  local force_dir=(+force_install_dir "${STEAM_INSTALL_DIR}")
  local app_update=(+app_update "${STEAM_APP_ID}")

  if [[ -n "${STEAM_BRANCH:-}" ]]; then
    log "Using Steam branch: ${STEAM_BRANCH}"
    app_update=(+app_update "${STEAM_APP_ID}" -beta "${STEAM_BRANCH}")
    if [[ -n "${STEAM_BRANCH_PASSWORD:-}" ]]; then
      app_update+=(-betapassword "${STEAM_BRANCH_PASSWORD}")
    fi
  fi

  if is_true "${STEAMCMD_VALIDATE:-true}"; then
    app_update+=(validate)
  fi

  if [[ -n "${STEAMCMD_EXTRA_ARGS:-}" ]]; then
    read -r -a extra <<<"${STEAMCMD_EXTRA_ARGS}"
    app_update+=("${extra[@]}")
  fi

  local cmd=(
    "${STEAMCMD}"
    "${force_dir[@]}"
    +login "${STEAM_LOGIN:-anonymous}" "${STEAM_PASSWORD:-}" "${STEAM_GUARD:-}"
    "${app_update[@]}"
    +quit
  )

  log "Updating Valheim via SteamCMD..."

  local attempts="${STEAMCMD_RETRIES:-3}"
  if [[ ! "${attempts}" =~ ^[0-9]+$ ]]; then
    attempts=3
  fi

  local i
  local rc=0
  for ((i = 1; i <= attempts; i++)); do
    set +e
    gosu steam "${cmd[@]}" 2>&1 | tee "${STEAMCMD_LOG_FILE:-/data/steam/steamcmd.log}"
    rc=${PIPESTATUS[0]}
    set -e
    if [[ "${rc}" -eq 0 ]]; then
      return 0
    fi
    log_err "SteamCMD failed (attempt ${i}/${attempts}, rc=${rc})."
    sleep $((i * 5))
  done

  return "${rc}"
}

ensure_steamclient() {
  # Some Unity/Steam servers expect steamclient.so under ~/.steam/sdk64
  local src="/home/steam/steamcmd/linux64/steamclient.so"
  local dst_dir="/home/steam/.steam/sdk64"
  local dst="${dst_dir}/steamclient.so"

  if [[ -f "${src}" ]]; then
    mkdir -p "${dst_dir}"
    if [[ ! -e "${dst}" ]]; then
      ln -s "${src}" "${dst}" >/dev/null 2>&1 || true
    fi
  fi
}

if ! steamcmd_update; then
  log_err "SteamCMD update failed."
fi
ensure_steamclient

server_dir="${STEAM_INSTALL_DIR}"
server_bin="${server_dir}/valheim_server.x86_64"
if [[ ! -x "${server_bin}" ]]; then
  log_err "ERROR: ${server_bin} not found or not executable."
  log_err "Check SteamCMD logs at ${STEAMCMD_LOG_FILE:-/data/steam/steamcmd.log}."
  exit 1
fi

name="${VALHEIM_SERVER_NAME:-RunOnFlux - Valheim}"
world="${VALHEIM_WORLD_NAME:-RunOnFlux}"
password="${VALHEIM_PASSWORD:-}"

if [[ -z "${password}" ]]; then
  log_err "ERROR: VALHEIM_PASSWORD must be set (Valheim requires a password; 5+ characters)."
  exit 1
fi
if [[ "${#password}" -lt 5 ]]; then
  log_err "ERROR: VALHEIM_PASSWORD must be at least 5 characters."
  exit 1
fi

public_flag=0
if is_true "${VALHEIM_PUBLIC:-true}"; then
  public_flag=1
fi

crossplay_args=()
if is_true "${VALHEIM_CROSSPLAY:-false}"; then
  crossplay_args+=("-crossplay")
fi

log_file="${VALHEIM_LOG_FILE-}"
extra_args="${VALHEIM_EXTRA_ARGS:-}"

if is_true "${VALHEIM_WRITE_STEAM_APPID_TXT:-true}"; then
  if [[ "${VALHEIM_STEAM_APP_ID}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${VALHEIM_STEAM_APP_ID}" >"${server_dir}/steam_appid.txt" || true
    if [[ "$(id -u)" -eq 0 ]]; then
      chown steam:steam "${server_dir}/steam_appid.txt" >/dev/null 2>&1 || true
    fi
  fi
fi

cmd=(
  "./valheim_server.x86_64"
  -name "${name}"
  -port "${VALHEIM_PORT}"
  -world "${world}"
  -password "${password}"
  -public "${public_flag}"
  -savedir "${VALHEIM_SAVEDIR}"
  -nographics
  -batchmode
  "${crossplay_args[@]}"
)
if [[ -n "${log_file}" ]]; then
  cmd+=(-logFile "${log_file}")
fi
if [[ -n "${extra_args}" ]]; then
  read -r -a extra_split <<<"${extra_args}"
  cmd+=("${extra_split[@]}")
fi

log "Starting server..."
log "Args: $(mask_args_for_log "${cmd[@]}")"

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:${STEAM_INSTALL_DIR}/linux64"
export SteamAppId="${VALHEIM_STEAM_APP_ID}"
export SteamGameId="${VALHEIM_STEAM_APP_ID}"

cd "${server_dir}"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu steam "${cmd[@]}"
else
  exec "${cmd[@]}"
fi
