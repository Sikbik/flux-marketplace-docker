#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[enshrouded] %s\n' "$*"
}

log_err() {
  printf '[enshrouded] %s\n' "$*" >&2
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
    log_err "ERROR: Not enough free disk space to install/update Enshrouded."
    log_err "Install path: ${STEAM_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log_err "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log_err "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    exit 1
  fi
}

write_json_tmp_replace() {
  local target="$1"
  local tmp="${target}.tmp"
  cat >"${tmp}"
  mv -f "${tmp}" "${target}"
}

steamcmd_update() {
  if ! is_true "${AUTO_UPDATE:-true}"; then
    log "AUTO_UPDATE=false; skipping SteamCMD update."
    return 0
  fi

  local steamcmd_home="${STEAMCMD_HOME:-/data/steam}"
  mkdir -p "${steamcmd_home}" >/dev/null 2>&1 || true

  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R steam:steam "${steamcmd_home}" >/dev/null 2>&1 || true
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
      elif grep -qi "No subscription" "${steamcmd_log}" 2>/dev/null; then
        steamcmd_error_kind="no_subscription"
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

  if [[ "${steamcmd_error_kind}" == "no_subscription" ]]; then
    log_err "SteamCMD indicates No subscription. Set STEAM_LOGIN/STEAM_PASSWORD to a Steam account that owns Enshrouded."
  fi

  log_err "SteamCMD failed (rc=${rc}). See ${steamcmd_log} and ${steamcmd_home}/Steam/logs for details."
  return "${rc}"
}

ensure_config() {
  local install_dir="${STEAM_INSTALL_DIR}"
  local config_dir="${ENS_CONFIG_DIR:-/config}"
  local save_dir="${ENS_SAVE_DIR:-/config/savegame}"
  local log_dir="${ENS_LOG_DIR:-/config/logs}"

  mkdir -p "${config_dir}" "${save_dir}" "${log_dir}"

  local config_path="${config_dir}/enshrouded_server.json"
  local exe_config_path="${install_dir}/enshrouded_server.json"

  # Keep the server's relative paths working while persisting config/saves/logs on /config.
  ln -sfn "${config_path}" "${exe_config_path}"
  ln -sfn "${save_dir}" "${install_dir}/savegame"
  ln -sfn "${log_dir}" "${install_dir}/logs"

  if [[ -n "${ENS_SERVER_JSON_B64:-}" ]]; then
    log "Writing enshrouded_server.json from ENS_SERVER_JSON_B64..."
    echo "${ENS_SERVER_JSON_B64}" | base64 -d | write_json_tmp_replace "${config_path}"
    return 0
  fi
  if [[ -n "${ENS_SERVER_JSON:-}" ]]; then
    log "Writing enshrouded_server.json from ENS_SERVER_JSON..."
    printf '%s\n' "${ENS_SERVER_JSON}" | write_json_tmp_replace "${config_path}"
    return 0
  fi

  if [[ ! -f "${config_path}" ]]; then
    log "Creating default enshrouded_server.json..."
    python3 - "${config_path}" <<'PY'
import json, os, sys

path = sys.argv[1]

def env(name, default=""):
    v = os.environ.get(name)
    if v is None:
        return default
    return v

def env_int(name, default):
    try:
        return int(str(env(name, str(default))).strip())
    except Exception:
        return default

def env_bool(name, default):
    v = str(env(name, "")).strip().lower()
    if v == "":
        return default
    return v in ("1", "true", "yes", "y", "on")

server_name = env("ENS_SERVER_NAME", "RunOnFlux - Enshrouded")
password = env("ENS_PASSWORD", "").strip()
slot_count = env_int("ENS_SLOT_COUNT", 16)
query_port = env_int("ENS_QUERY_PORT", 15637)
ip = env("ENS_IP", "0.0.0.0")
preset = env("ENS_GAME_SETTINGS_PRESET", "Default")
voice_mode = env("ENS_VOICE_CHAT_MODE", "Proximity")
enable_voice = env_bool("ENS_ENABLE_VOICE_CHAT", False)
enable_text = env_bool("ENS_ENABLE_TEXT_CHAT", False)

config = {
  "name": server_name,
  "password": "",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": ip,
  "queryPort": query_port,
  "slotCount": slot_count,
  "voiceChatMode": voice_mode,
  "enableVoiceChat": enable_voice,
  "enableTextChat": enable_text,
  "gameSettingsPreset": preset,
}

# Flux-friendly default: a single password that grants "legacy" full permissions
# via a single Default group. This avoids multi-password complexity for most users.
if password:
  config["userGroups"] = [{
    "name": "Default",
    "password": password,
    "canKickBan": True,
    "canAccessInventories": True,
    "canEditBase": True,
    "canExtendBase": True,
    "reservedSlots": 0,
  }]

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, sort_keys=False)
    f.write("\n")
PY
  fi

  if is_true "${MANAGE_CONFIG:-true}" && [[ "${ENS_CONFIG_APPLY_MODE:-always}" == "always" ]]; then
    log "Applying env vars to enshrouded_server.json..."
    python3 - "${config_path}" <<'PY'
import json, os, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

def get(name):
    v = os.environ.get(name)
    if v is None:
        return None
    v = str(v).strip()
    if v == "":
        return None
    return v

def get_int(name):
    v = get(name)
    if v is None:
        return None
    try:
        return int(v)
    except Exception:
        return None

def get_bool(name):
    v = get(name)
    if v is None:
        return None
    return v.lower() in ("1", "true", "yes", "y", "on")

name = get("ENS_SERVER_NAME")
if name is not None:
    cfg["name"] = name

ip = get("ENS_IP")
if ip is not None:
    cfg["ip"] = ip

qp = get_int("ENS_QUERY_PORT")
if qp is not None:
    cfg["queryPort"] = qp

slots = get_int("ENS_SLOT_COUNT")
if slots is not None:
    cfg["slotCount"] = slots

preset = get("ENS_GAME_SETTINGS_PRESET")
if preset is not None:
    cfg["gameSettingsPreset"] = preset

vcm = get("ENS_VOICE_CHAT_MODE")
if vcm is not None:
    cfg["voiceChatMode"] = vcm

evc = get_bool("ENS_ENABLE_VOICE_CHAT")
if evc is not None:
    cfg["enableVoiceChat"] = evc

etc = get_bool("ENS_ENABLE_TEXT_CHAT")
if etc is not None:
    cfg["enableTextChat"] = etc

password = get("ENS_PASSWORD")
if password is not None:
    # Keep it simple: set/refresh a single Default group with full permissions.
    cfg["password"] = ""
    cfg["userGroups"] = [{
        "name": "Default",
        "password": password,
        "canKickBan": True,
        "canAccessInventories": True,
        "canEditBase": True,
        "canExtendBase": True,
        "reservedSlots": 0,
    }]

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, sort_keys=False)
    f.write("\n")
os.replace(tmp, path)
PY
  fi
}

start_xvfb_if_needed() {
  if ! is_true "${USE_XVFB:-true}"; then
    return 0
  fi
  export DISPLAY=":${XVFB_DISPLAY:-99}"
  if pgrep -f "Xvfb ${DISPLAY}" >/dev/null 2>&1; then
    return 0
  fi
  log "Starting Xvfb on ${DISPLAY}..."
  # shellcheck disable=SC2086
  run_as_steam Xvfb "${DISPLAY}" ${XVFB_ARGS:-"-screen 0 1024x768x24 -nolisten tcp -ac"} >/dev/null 2>&1 &
}

run_as_steam() {
  gosu steam "$@"
}

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"
STEAM_APP_ID="${STEAM_APP_ID:-2278520}"
ENS_EXE_NAME="${ENS_EXE_NAME:-enshrouded_server.exe}"
ENS_EXE_PATH="${STEAM_INSTALL_DIR}/${ENS_EXE_NAME}"

WINEPREFIX="${WINEPREFIX:-/opt/wine/prefix}"
WINEARCH="${WINEARCH:-win64}"
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

log "=========================================="
log "  Enshrouded Dedicated Server"
log "  (SteamCMD + Wine, Flux-friendly)"
log "=========================================="
log "Steam AppID:  ${STEAM_APP_ID}"
log "Install dir:  ${STEAM_INSTALL_DIR}"
log "Config dir:   ${ENS_CONFIG_DIR:-/config}"
log "Query port:   ${ENS_QUERY_PORT:-15637}/udp"
log "Wine prefix:  ${WINEPREFIX}"

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

mkdir -p "${STEAM_INSTALL_DIR}" "${ENS_CONFIG_DIR:-/config}" "${ENS_SAVE_DIR:-/config/savegame}" "${ENS_LOG_DIR:-/config/logs}" "$(dirname "${WINEPREFIX}")"
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ "${id_changed}" == "true" ]]; then
    chown -R steam:steam "${STEAM_INSTALL_DIR}" "${ENS_CONFIG_DIR:-/config}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  else
    chown steam:steam "${STEAM_INSTALL_DIR}" "${ENS_CONFIG_DIR:-/config}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
  fi
fi

if is_true "${HARDEN_FLUX_VOLUME_BROWSER:-true}"; then
  chmod 700 "${STEAM_INSTALL_DIR}" "$(dirname "${STEAMCMD_HOME:-/data/steam}")" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
else
  chmod 755 "${STEAM_INSTALL_DIR}" "$(dirname "${STEAMCMD_HOME:-/data/steam}")" "${STEAMCMD_HOME:-/data/steam}" >/dev/null 2>&1 || true
fi
chmod 755 "${ENS_CONFIG_DIR:-/config}" "${ENS_SAVE_DIR:-/config/savegame}" "${ENS_LOG_DIR:-/config/logs}" >/dev/null 2>&1 || true

mkdir -p "${WINEPREFIX}"
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R steam:steam "${WINEPREFIX}" >/dev/null 2>&1 || true
fi

disk_preflight
steamcmd_update

if [[ ! -f "${ENS_EXE_PATH}" ]]; then
  log_err "ERROR: Server binary not found after SteamCMD update: ${ENS_EXE_PATH}"
  log_err "SteamCMD log: ${STEAMCMD_LOG_FILE}"
  exit 1
fi

ensure_config
start_xvfb_if_needed

log "Starting Enshrouded server..."

shutdown_grace="${ENS_SHUTDOWN_GRACE:-30}"
if [[ ! "${shutdown_grace}" =~ ^[0-9]+$ ]]; then
  shutdown_grace=30
fi

server_pid=""
term_handler() {
  log "Shutdown requested. Stopping server (grace: ${shutdown_grace}s)..."
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" >/dev/null 2>&1; then
    kill -TERM "${server_pid}" >/dev/null 2>&1 || true
    local waited=0
    while kill -0 "${server_pid}" >/dev/null 2>&1; do
      if (( waited >= shutdown_grace )); then
        log "Grace period exceeded; sending SIGKILL."
        kill -KILL "${server_pid}" >/dev/null 2>&1 || true
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
  fi
}

trap term_handler TERM INT

cd "${STEAM_INSTALL_DIR}"

set +e
run_as_steam wine64 "./${ENS_EXE_NAME}" ${ENS_EXTRA_ARGS:-} &
server_pid="$!"
wait "${server_pid}"
rc="$?"
set -e

log "Server exited with code ${rc}."
exit "${rc}"
