#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[terraria] %s\n' "$*"
}

log_err() {
  printf '[terraria] %s\n' "$*" >&2
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

sanitize_filename() {
  local s
  s="$(trim "${1:-}")"
  s="${s//[^a-zA-Z0-9._ -]/}"
  s="${s// /_}"
  s="${s#_}"
  s="${s%_}"
  if [[ -z "${s}" ]]; then
    s="world"
  fi
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

  local required_gb="${MIN_FREE_GB:-2}"
  if [[ ! "${required_gb}" =~ ^[0-9]+$ ]]; then
    required_gb=2
  fi
  local required_bytes=$((required_gb * 1024 * 1024 * 1024))

  local avail_bytes
  avail_bytes="$(bytes_available_on_path "${TERRARIA_INSTALL_DIR}")"
  if [[ -z "${avail_bytes}" ]]; then
    log "Disk preflight: unable to determine free space for ${TERRARIA_INSTALL_DIR} (skipping)"
    return 0
  fi

  local avail_gb=$((avail_bytes / 1024 / 1024 / 1024))
  local mountpoint
  mountpoint="$(mountpoint_for_path "${TERRARIA_INSTALL_DIR}")"

  if (( avail_bytes < required_bytes )); then
    log_err "ERROR: Not enough free disk space to install/update Terraria Dedicated Server."
    log_err "Install path: ${TERRARIA_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log_err "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log_err "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    exit 1
  fi
}

TERRARIA_INSTALL_DIR="${TERRARIA_INSTALL_DIR:-/data/server}"
TERRARIA_CONFIG_PATH="${TERRARIA_CONFIG_PATH:-/config/serverconfig.txt}"

WORLD_DIR="/config/worlds"
WORLD_NAME="${TERRARIA_WORLD_NAME:-RunOnFlux World}"
WORLD_FILE="${TERRARIA_WORLD_FILE:-}"
if [[ -z "${WORLD_FILE}" ]]; then
  WORLD_FILE="$(sanitize_filename "${WORLD_NAME}")"
fi
WORLD_PATH="${WORLD_DIR}/${WORLD_FILE}.wld"

PORT="${TERRARIA_PORT:-7777}"
if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
  PORT=7777
fi

PASSWORD="${TERRARIA_SERVER_PASSWORD:-}"

id_changed="false"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "${PUID:-}" ]] && [[ "${PUID}" != "1000" ]]; then
    log "Updating UID to ${PUID}..."
    if usermod -u "${PUID}" terraria; then
      id_changed="true"
    fi
  fi
  if [[ -n "${PGID:-}" ]] && [[ "${PGID}" != "1000" ]]; then
    log "Updating GID to ${PGID}..."
    if groupmod -g "${PGID}" terraria; then
      id_changed="true"
    fi
  fi
else
  if [[ -n "${PUID:-}" || -n "${PGID:-}" ]]; then
    log "Warning: PUID/PGID set but container is not running as root; skipping user/group modifications."
  fi
fi

mkdir -p "${TERRARIA_INSTALL_DIR}" "$(dirname "${TERRARIA_CONFIG_PATH}")" "${WORLD_DIR}"
touch /config/banlist.txt >/dev/null 2>&1 || true

if [[ "$(id -u)" -eq 0 ]]; then
  chown -R terraria:terraria "${TERRARIA_INSTALL_DIR}" /config >/dev/null 2>&1 || true
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-true}"; then
  chmod 700 "${TERRARIA_INSTALL_DIR}" >/dev/null 2>&1 || true
else
  chmod 755 "${TERRARIA_INSTALL_DIR}" >/dev/null 2>&1 || true
fi
chmod 755 /config "${WORLD_DIR}" >/dev/null 2>&1 || true

disk_preflight

guess_latest_version_from_wiki() {
  local url="${TERRARIA_WIKI_URL:-https://terraria.wiki.gg/wiki/Server}"
  local html
  if ! html="$(curl -fsSL "${url}" 2>/dev/null)"; then
    return 1
  fi

  # Pick the highest `terraria-server-####.zip` found on the page.
  echo "${html}" \
    | tr '\r\n' ' ' \
    | grep -Eo 'terraria-server-[0-9]+\.zip' \
    | sed -E 's/^terraria-server-([0-9]+)\.zip$/\1/' \
    | sort -n \
    | tail -n 1
}

resolve_server_version() {
  local version="${TERRARIA_SERVER_VERSION:-}"
  if [[ -n "${version}" ]]; then
    printf '%s' "${version}"
    return 0
  fi

  if [[ -n "${TERRARIA_SERVER_URL:-}" ]]; then
    printf '%s' ""
    return 0
  fi

  version="$(guess_latest_version_from_wiki || true)"
  if [[ -z "${version}" ]]; then
    return 1
  fi
  printf '%s' "${version}"
}

terraria_download_url() {
  if [[ -n "${TERRARIA_SERVER_URL:-}" ]]; then
    printf '%s' "${TERRARIA_SERVER_URL}"
    return 0
  fi

  local version="${1:-}"
  if [[ -z "${version}" ]]; then
    return 1
  fi

  printf 'https://terraria.org/api/download/pc-dedicated-server/terraria-server-%s.zip' "${version}"
}

download_and_extract_server() {
  local version=""
  version="$(resolve_server_version)" || true

  local url
  url="$(terraria_download_url "${version}")" || {
    log_err "ERROR: Unable to determine Terraria dedicated server download URL."
    log_err "Set TERRARIA_SERVER_VERSION (e.g. 1450) or TERRARIA_SERVER_URL."
    exit 1
  }

  local dist_dir="${TERRARIA_INSTALL_DIR}/dist"
  local version_file="${dist_dir}/.version"
  local zip_path="/tmp/terraria-server.zip"

  if [[ -d "${dist_dir}" ]] && find "${dist_dir}" -maxdepth 6 -name 'TerrariaServer.bin.x86_64' -type f | grep -q .; then
    if ! is_true "${AUTO_UPDATE:-true}"; then
      log "AUTO_UPDATE=false; using existing server install at ${dist_dir}"
      return 0
    fi

    if [[ -n "${version}" ]] && [[ -f "${version_file}" ]] && [[ "$(cat "${version_file}" 2>/dev/null || true)" == "${version}" ]]; then
      log "Server version ${version} already installed; skipping download."
      return 0
    fi
  fi

  log "Downloading Terraria dedicated server..."
  log "URL: ${url}"
  rm -f "${zip_path}"
  curl -fsSL -o "${zip_path}" "${url}"

  rm -rf "${dist_dir}.new"
  mkdir -p "${dist_dir}.new"
  unzip -q "${zip_path}" -d "${dist_dir}.new"

  rm -rf "${dist_dir}"
  mv "${dist_dir}.new" "${dist_dir}"
  rm -f "${zip_path}"

  if [[ -n "${version}" ]]; then
    printf '%s' "${version}" >"${version_file}" || true
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R terraria:terraria "${dist_dir}" >/dev/null 2>&1 || true
  fi
}

find_server_bin() {
  local dist_dir="${TERRARIA_INSTALL_DIR}/dist"
  local bin
  bin="$(find "${dist_dir}" -maxdepth 6 -type f -name 'TerrariaServer.bin.x86_64' 2>/dev/null | head -n 1 || true)"
  if [[ -z "${bin}" ]]; then
    return 1
  fi
  printf '%s' "${bin}"
}

write_config() {
  if ! is_true "${MANAGE_CONFIG:-true}"; then
    log "MANAGE_CONFIG=false; skipping config generation."
    return 0
  fi

  local cfg="${TERRARIA_CONFIG_PATH}"
  mkdir -p "$(dirname "${cfg}")"

  local max_players="${TERRARIA_MAX_PLAYERS:-16}"
  local autocreate="${TERRARIA_AUTOCREATE:-2}"
  local seed="${TERRARIA_SEED:-}"
  local motd="${TERRARIA_MOTD:-}"
  local difficulty="${TERRARIA_DIFFICULTY:-0}"

  local secure=1
  if ! is_true "${TERRARIA_SECURE:-true}"; then
    secure=0
  fi

  local upnp=0
  if is_true "${TERRARIA_UPNP:-false}"; then
    upnp=1
  fi

  local lines=()
  lines+=("worldpath=${WORLD_DIR}")
  lines+=("world=${WORLD_PATH}")
  lines+=("worldname=${WORLD_NAME}")
  lines+=("port=${PORT}")
  lines+=("maxplayers=${max_players}")
  lines+=("secure=${secure}")
  lines+=("upnp=${upnp}")
  lines+=("banlist=/config/banlist.txt")

  if [[ -n "${PASSWORD}" ]]; then
    lines+=("password=${PASSWORD}")
  fi
  if [[ -n "${motd}" ]]; then
    lines+=("motd=${motd}")
  fi
  if [[ -n "${autocreate}" ]]; then
    lines+=("autocreate=${autocreate}")
  fi
  if [[ -n "${seed}" ]]; then
    lines+=("seed=${seed}")
  fi
  if [[ -n "${difficulty}" ]]; then
    lines+=("difficulty=${difficulty}")
  fi

  {
    printf '%s\n' "# Generated by terraria-flux image"
    printf '%s\n' "# Edit this file or set MANAGE_CONFIG=false to manage it yourself."
    printf '\n'
    printf '%s\n' "${lines[@]}"
  } >"${cfg}"

  if [[ "$(id -u)" -eq 0 ]]; then
    chown terraria:terraria "${cfg}" >/dev/null 2>&1 || true
  fi
  chmod 600 "${cfg}" >/dev/null 2>&1 || true
}

log "=========================================="
log "  Terraria Dedicated Server (Headless)"
log "  (Flux-friendly)"
log "=========================================="
log "Install dir: ${TERRARIA_INSTALL_DIR}"
log "Config:      ${TERRARIA_CONFIG_PATH}"
log "World file:  ${WORLD_PATH}"
log "Port:        ${PORT}/tcp"
if [[ -n "${PASSWORD}" ]]; then
  log "Password:    <set>"
else
  log "Password:    <not set>"
fi

download_and_extract_server
write_config

cfg_link="${TERRARIA_INSTALL_DIR}/serverconfig.txt"
ln -sf "${TERRARIA_CONFIG_PATH}" "${cfg_link}"
ln -sf /config/banlist.txt "${TERRARIA_INSTALL_DIR}/banlist.txt" >/dev/null 2>&1 || true

server_bin="$(find_server_bin)" || {
  log_err "ERROR: Could not locate TerrariaServer.bin.x86_64 after extraction."
  log_err "Check that the download URL is valid and the zip contains a Linux server build."
  exit 1
}
chmod +x "${server_bin}" >/dev/null 2>&1 || true

log "Starting server..."
cd "$(dirname "${server_bin}")"

extra_args="${TERRARIA_EXTRA_ARGS:-}"

if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu terraria "${server_bin}" -config "${cfg_link}" ${extra_args}
else
  exec "${server_bin}" -config "${cfg_link}" ${extra_args}
fi
