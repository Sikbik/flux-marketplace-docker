#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[starrupture] %s\n' "$*"
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
    return
  fi

  local required_gb="${MIN_FREE_GB:-30}"
  local required_bytes=$((required_gb * 1024 * 1024 * 1024))

  local avail_bytes
  avail_bytes="$(bytes_available_on_path "${STEAM_INSTALL_DIR}")"
  if [[ -z "${avail_bytes}" ]]; then
    log "Disk preflight: unable to determine free space for ${STEAM_INSTALL_DIR} (skipping)"
    return
  fi

  local avail_gb=$((avail_bytes / 1024 / 1024 / 1024))
  local mountpoint
  mountpoint="$(mountpoint_for_path "${STEAM_INSTALL_DIR}")"

  if (( avail_bytes < required_bytes )); then
    log "ERROR: Not enough free disk space to install/update StarRupture."
    log "Install path: ${STEAM_INSTALL_DIR} (mount: ${mountpoint:-unknown})"
    log "Required: ${required_gb} GB free; Available: ${avail_gb} GB free"
    log "Tip: On Flux, the requested HDD applies to the mounted app volume (containerData), not the container root filesystem (/)."
    log "Tip: If ${STEAM_INSTALL_DIR} is on /, you're using the node's Docker disk. Use a mounted path (e.g. /data/server) to use the allocated HDD."
    exit 1
  fi
}

is_separate_mount() {
  local path="$1"
  [[ -e "${path}" ]] || return 1
  local root_mount
  root_mount="$(mountpoint_for_path "/")"
  local path_mount
  path_mount="$(mountpoint_for_path "${path}")"
  [[ -n "${root_mount}" && -n "${path_mount}" && "${path_mount}" != "${root_mount}" ]]
}

select_install_dir() {
  if [[ -n "${STEAM_INSTALL_DIR:-}" ]]; then
    return
  fi

  local required_gb="${MIN_FREE_GB:-30}"
  local required_bytes=$((required_gb * 1024 * 1024 * 1024))

  local opt_path="/opt/server"
  local data_path="/data/server"

  local opt_avail=""
  opt_avail="$(bytes_available_on_path "${opt_path}")"

  local data_avail=""
  if is_separate_mount "/data"; then
    data_avail="$(bytes_available_on_path "${data_path}")"
  fi

  # Prefer rootfs when it has enough space (keeps large installs out of Flux volumes).
  if [[ -n "${opt_avail}" ]] && (( opt_avail >= required_bytes )); then
    STEAM_INSTALL_DIR="${opt_path}"
    return
  fi

  # Fall back to /data when it is a separate mounted volume with enough space.
  if [[ -n "${data_avail}" ]] && (( data_avail >= required_bytes )); then
    STEAM_INSTALL_DIR="${data_path}"
    return
  fi

  # Neither meets the threshold; pick whichever has more free space so the
  # error message is as actionable as possible.
  if [[ -n "${data_avail}" ]] && [[ -z "${opt_avail}" || "${data_avail}" -gt "${opt_avail}" ]]; then
    STEAM_INSTALL_DIR="${data_path}"
  else
    STEAM_INSTALL_DIR="${opt_path}"
  fi
}

steamcmd_update() {
  local steamcmd_home="${STEAMCMD_HOME:-}"
  if [[ -z "${steamcmd_home}" ]]; then
    if is_separate_mount "/data"; then
      steamcmd_home="/data/steam"
    else
      steamcmd_home="/tmp/steam"
    fi
  fi

  mkdir -p "${steamcmd_home}"

  # SteamCMD uses $HOME/Steam for caches/config. On Flux, /root may be
  # constrained, so keep Steam state on a writable mount by default.
  export HOME="${steamcmd_home}"

  local steamcmd_log="${STEAMCMD_LOG_FILE:-/tmp/steamcmd.log}"
  local steamcmd_error_kind=""

  run_steamcmd() {
    steamcmd_error_kind=""

    local -a cmd
    cmd=(/home/steam/steamcmd/steamcmd.sh +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1)

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

    log "Running SteamCMD app_update for ${STEAM_APP_ID}..."
    rm -f "${steamcmd_log}" >/dev/null 2>&1 || true

    mkdir -p "${STEAM_INSTALL_DIR}" >/dev/null 2>&1 || true

    local rc=0
    if [[ "${STEAMCMD_RUN_AS:-steam}" == "steam" ]] && [[ "$(id -u)" -eq 0 ]]; then
      chown -R steam:steam "${STEAM_INSTALL_DIR}" || true
      chown -R steam:steam "${steamcmd_home}" || true
      local cmd_string
      cmd_string="$(printf '%q ' "${cmd[@]}")"
      set +e
      su - steam -c "HOME=\"${steamcmd_home}\" ${cmd_string}" 2>&1 | tee "${steamcmd_log}"
      rc="${PIPESTATUS[0]}"
      set -e
    else
      set +e
      "${cmd[@]}" 2>&1 | tee "${steamcmd_log}"
      rc="${PIPESTATUS[0]}"
      set -e
    fi

    if (( rc != 0 )); then
      if [[ -f "${steamcmd_log}" ]]; then
        if grep -q "Missing configuration" "${steamcmd_log}" 2>/dev/null; then
          steamcmd_error_kind="missing_configuration"
          log "ERROR: SteamCMD failed (Missing configuration)."
        elif grep -q "Missing file permissions" "${steamcmd_log}" 2>/dev/null; then
          steamcmd_error_kind="missing_file_permissions"
          log "ERROR: SteamCMD failed (Missing file permissions)."
        elif grep -q "Disk write failure" "${steamcmd_log}" 2>/dev/null; then
          steamcmd_error_kind="disk_write_failure"
          log "ERROR: SteamCMD failed (Disk write failure)."
        fi
      fi

      log "Diagnostics:"
      log "User: $(id -u):$(id -g) ($(id -un 2>/dev/null || true))"
      log "HOME: ${HOME}"
      log "STEAM_INSTALL_DIR: ${STEAM_INSTALL_DIR}"
      log "mount (filtered):"
      mount | grep -E ' on /(data|saves) ' 2>/dev/null || true
      log "df (bytes):"
      df -h "${steamcmd_home}" "${STEAM_INSTALL_DIR}" 2>/dev/null || true
      log "df (inodes):"
      df -hi "${steamcmd_home}" "${STEAM_INSTALL_DIR}" 2>/dev/null || true

      log "stat:"
      stat -c '%A %u:%g %s %n' "${steamcmd_home}" "${STEAM_INSTALL_DIR}" 2>/dev/null || true

      log "write test:"
      (mkdir -p "${steamcmd_home}/.write-test" && echo ok > "${steamcmd_home}/.write-test/test.txt" && rm -rf "${steamcmd_home}/.write-test") >/dev/null 2>&1 \
        && log "steamcmd_home ok" \
        || log "steamcmd_home FAILED"
      (mkdir -p "${STEAM_INSTALL_DIR}/.write-test" && echo ok > "${STEAM_INSTALL_DIR}/.write-test/test.txt" && rm -rf "${STEAM_INSTALL_DIR}/.write-test") >/dev/null 2>&1 \
        && log "install dir ok" \
        || log "install dir FAILED"

      log "Steam logs (tail):"
      tail -n 80 "${steamcmd_home}/Steam/logs/stderr.txt" 2>/dev/null || true
      tail -n 80 "${steamcmd_home}/Steam/logs/bootstrap_log.txt" 2>/dev/null || true

      return "${rc}"
    fi

    if [[ -f "${steamcmd_log}" ]] && grep -q "state is 0x202 after update job" "${steamcmd_log}" 2>/dev/null; then
      log "ERROR: SteamCMD reported app state 0x202 after update job (commonly insufficient disk space at install path)."
      local avail_bytes
      avail_bytes="$(bytes_available_on_path "${STEAM_INSTALL_DIR}")"
      if [[ -n "${avail_bytes}" ]]; then
        log "Free space at install path: $((avail_bytes / 1024 / 1024 / 1024)) GB"
      fi
      log "If this keeps happening on Flux, try a different node, or disable validate via STEAMCMD_VALIDATE=false."
      return 1
    fi

    return 0
  }

  run_steamcmd
  local rc=$?
  if (( rc == 0 )); then
    return 0
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

  if [[ "${STEAMCMD_RUN_AS:-steam}" == "root" ]] && [[ "$(id -u)" -eq 0 ]] && is_true "${STEAMCMD_RETRY_AS_STEAM_ON_FAIL:-true}"; then
    log "SteamCMD failed as root; retrying once with STEAMCMD_RUN_AS=steam..."
    STEAMCMD_RUN_AS=steam run_steamcmd
    rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  if [[ "${STEAMCMD_RUN_AS:-steam}" == "steam" ]] && [[ "$(id -u)" -eq 0 ]] && is_true "${STEAMCMD_RETRY_AS_ROOT_ON_FAIL:-true}"; then
    log "SteamCMD failed as steam; retrying once with STEAMCMD_RUN_AS=root..."
    STEAMCMD_RUN_AS=root run_steamcmd
    rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  return "${rc}"
}

init_wine_prefix() {
  mkdir -p "${WINEPREFIX}"
  if [[ ! -d "${WINEPREFIX}/drive_c" ]]; then
    log "Initializing Wine prefix at ${WINEPREFIX}..."
    "${WINE_BIN}" cmd /c echo Wine prefix initialized >/dev/null 2>&1 || true
  fi
}

STEAM_APP_ID="${STEAM_APP_ID:-3809400}"
SYNC_SAVES_ONLY="${SYNC_SAVES_ONLY:-false}"

# SAVED_DIR is the Unreal "Saved" directory root.
# Legacy alias: SAVES_DIR.
SAVED_DIR="${SAVED_DIR:-${SAVES_DIR:-/saves}}"

# When SYNC_SAVES_ONLY=true, only the SaveGames directory (and optionally
# password files) are expected to be synced (Flux g:/). SAVEGAMES_DIR is the
# synced folder.
SAVEGAMES_DIR="${SAVEGAMES_DIR:-}"

SR_AUTO_START="${SR_AUTO_START:-true}"
SR_ADMIN_PASSWORD="${SR_ADMIN_PASSWORD:-}"
SR_PLAYER_PASSWORD="${SR_PLAYER_PASSWORD:-}"
SR_ADMIN_PASSWORD_TOKEN="${SR_ADMIN_PASSWORD_TOKEN:-}"
SR_PLAYER_PASSWORD_TOKEN="${SR_PLAYER_PASSWORD_TOKEN:-}"
SR_FORCE_PASSWORD_FILES="${SR_FORCE_PASSWORD_FILES:-false}"
SR_SESSION_NAME="${SR_SESSION_NAME:-}"
SR_CREDENTIALS_WAIT_SECS="${SR_CREDENTIALS_WAIT_SECS:-60}"
SR_PASSWORD_SYNC_INTERVAL_SECS="${SR_PASSWORD_SYNC_INTERVAL_SECS:-10}"
SR_REMOTE_WAIT_SECS="${SR_REMOTE_WAIT_SECS:-600}"
SR_REMOTE_HOST="${SR_REMOTE_HOST:-127.0.0.1}"
SR_REMOTE_PORT="${SR_REMOTE_PORT:-}"
SR_REMOTE_PORTS="${SR_REMOTE_PORTS:-}"
SR_WINE_PID="${SR_WINE_PID:-}"

# Prefer a rootfs install when there's enough space so Flux "volume browser"
# cannot traverse the large Steam/Wine directories. If the node's Docker disk is
# too small, fall back to a mounted volume at /data (if present).
select_install_dir

if [[ -z "${WINEPREFIX:-}" ]]; then
  if [[ -d "/data/wine" || -d "/data/wine/prefix" ]]; then
    WINEPREFIX="/data/wine/prefix"
  else
    WINEPREFIX="/opt/wine/prefix"
  fi
fi

case "${WINEPREFIX}" in
  /opt/wine|/opt/wine/)
    WINEPREFIX="/opt/wine/prefix"
    ;;
  /data/wine|/data/wine/)
    WINEPREFIX="/data/wine/prefix"
    ;;
esac

WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEDLLOVERRIDES

HARDEN_FLUX_VOLUME_BROWSER="${HARDEN_FLUX_VOLUME_BROWSER:-false}"

if [[ -z "${STEAMCMD_RUN_AS:-}" ]]; then
  STEAMCMD_RUN_AS="steam"
  if is_true "${HARDEN_FLUX_VOLUME_BROWSER}" && [[ "$(id -u)" -eq 0 ]]; then
    STEAMCMD_RUN_AS="root"
  fi
fi

harden_path_for_flux_browser() {
  local path="$1"
  [[ -n "${path}" ]] || return
  [[ "$(id -u)" -eq 0 ]] || return
  mkdir -p "${path}" >/dev/null 2>&1 || true
  chown root:root "${path}" >/dev/null 2>&1 || true
  chmod 700 "${path}" >/dev/null 2>&1 || true
}

harden_large_dirs_for_flux_browser() {
  if ! is_true "${HARDEN_FLUX_VOLUME_BROWSER}"; then
    return
  fi
  [[ "$(id -u)" -eq 0 ]] || return

  if [[ "${STEAM_INSTALL_DIR}" == /data/* ]]; then
    harden_path_for_flux_browser "${STEAM_INSTALL_DIR}"
  fi

  if [[ "${WINEPREFIX}" == /data/* ]]; then
    harden_path_for_flux_browser "$(dirname "${WINEPREFIX}")"
  fi
}

hardening_notice_printed=false
if is_true "${HARDEN_FLUX_VOLUME_BROWSER}" && [[ "${STEAMCMD_RUN_AS}" == "steam" ]]; then
  hardening_notice_printed=true
  log "Warning: HARDEN_FLUX_VOLUME_BROWSER=true but STEAMCMD_RUN_AS=steam; SteamCMD may not be able to write to hardened paths."
fi

detect_server_exe() {
  for candidate in \
    "${STEAM_INSTALL_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe" \
    "${STEAM_INSTALL_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS.exe" \
    "${STEAM_INSTALL_DIR}/StarRupture/StarRuptureServerEOS.exe" \
    "${STEAM_INSTALL_DIR}/StarRuptureServerEOS.exe" \
    "${STEAM_INSTALL_DIR}/StarRuptureServerEOS-Win64-Shipping.exe"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_server_exe() {
  if [[ -n "${SERVER_EXE:-}" ]]; then
    return 0
  fi

  local found=""
  found="$(detect_server_exe 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    SERVER_EXE="${found}"
    return
  fi

  SERVER_EXE="${STEAM_INSTALL_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe"
}

DEFAULT_PORT="${DEFAULT_PORT:-7777}"
SERVER_PORT="${SERVER_PORT:-${DEFAULT_PORT}}"
QUERY_PORT="${QUERY_PORT:-27015}"
SERVER_NAME="${SERVER_NAME:-starrupture-server}"
MULTIHOME="${MULTIHOME:-}"

export PATH="/usr/lib/wine:${PATH}"

WINE_BIN="${WINE_BIN:-}"
if [[ -z "${WINE_BIN}" ]]; then
  if command -v wine >/dev/null 2>&1; then
    WINE_BIN="$(command -v wine)"
  elif command -v wine64 >/dev/null 2>&1; then
    WINE_BIN="$(command -v wine64)"
  elif [[ -x /usr/lib/wine/wine ]]; then
    WINE_BIN="/usr/lib/wine/wine"
  elif [[ -x /usr/lib/wine/wine64 ]]; then
    WINE_BIN="/usr/lib/wine/wine64"
  fi
fi

if [[ -z "${WINE_BIN}" ]]; then
  log "wine binary not found (set WINE_BIN to override)"
  exit 1
fi

latest_save_file_in_dir() {
  local dir="$1"
  find "${dir}" -type f -name '*.sav' -printf '%T@ %p\n' 2>/dev/null | \
    sort -nr | head -n 1 | cut -d' ' -f2-
}

parse_save_data_file() {
  local save_data_path="$1"
  [[ -f "${save_data_path}" ]] || return 1
  local s
  s="$(tr -d '\r\n' < "${save_data_path}" 2>/dev/null || true)"
  [[ -n "${s}" ]] || return 1
  s="${s#/}"
  local session="${s%%/*}"
  local save_base="${s#*/}"
  [[ -n "${session}" && -n "${save_base}" && "${save_base}" != "${session}" ]] || return 1
  printf '%s\n' "${session}" "${save_base}"
}

setup_persistence() {
  if is_true "${SYNC_SAVES_ONLY}"; then
    if [[ -z "${SAVEGAMES_DIR}" ]]; then
      SAVEGAMES_DIR="/saves"
    fi
    if [[ -z "${SAVED_DIR}" || "${SAVED_DIR}" == "/saves" ]]; then
      if is_separate_mount "/data"; then
        SAVED_DIR="/data/saved"
      else
        SAVED_DIR="/opt/saved"
      fi
    fi
  else
    if [[ -z "${SAVEGAMES_DIR}" ]]; then
      SAVEGAMES_DIR="${SAVED_DIR}/SaveGames"
    fi
  fi

  mkdir -p "${SAVED_DIR}"
  mkdir -p "${SAVEGAMES_DIR}"

  if is_true "${SYNC_SAVES_ONLY}"; then
    local sg_link="${SAVED_DIR}/SaveGames"
    if [[ -d "${sg_link}" && ! -L "${sg_link}" ]]; then
      if [[ -z "$(ls -A "${SAVEGAMES_DIR}" 2>/dev/null)" ]]; then
        mv "${sg_link}"/* "${SAVEGAMES_DIR}/" 2>/dev/null || true
      fi
      rm -rf "${sg_link}"
    fi
    ln -sfn "${SAVEGAMES_DIR}" "${sg_link}"
  else
    mkdir -p "${SAVED_DIR}/SaveGames"
  fi

  local saved_dir="${STEAM_INSTALL_DIR}/StarRupture/Saved"
  mkdir -p "$(dirname "${saved_dir}")"

  if [[ -d "${saved_dir}" && ! -L "${saved_dir}" ]]; then
    if [[ -z "$(ls -A "${SAVED_DIR}" 2>/dev/null)" ]]; then
      mv "${saved_dir}"/* "${SAVED_DIR}/" 2>/dev/null || true
    fi
    rm -rf "${saved_dir}"
  fi
  ln -sfn "${SAVED_DIR}" "${saved_dir}"

  local users_dir="${WINEPREFIX}/drive_c/users"
  if [[ -d "${users_dir}" ]]; then
    for user_dir in "${users_dir}"/*; do
      [[ -d "${user_dir}" ]] || continue
      local appdata_saved="${user_dir}/AppData/Local/StarRupture/Saved"
      mkdir -p "$(dirname "${appdata_saved}")"
      if [[ -d "${appdata_saved}" && ! -L "${appdata_saved}" ]]; then
        rm -rf "${appdata_saved}"
      fi
      ln -sfn "${SAVED_DIR}" "${appdata_saved}"
    done
  fi

  local password_root="${SAVED_DIR}"
  if is_true "${SYNC_SAVES_ONLY}"; then
    password_root="${SAVEGAMES_DIR}"
  fi

  local server_exe_dir=""
  if [[ -n "${SERVER_EXE:-}" ]]; then
    server_exe_dir="$(dirname "${SERVER_EXE}")"
  fi

  sync_password_file() {
    local src="$1"
    local dest="$2"

    [[ -n "${src}" && -n "${dest}" ]] || return 0
    [[ -s "${src}" ]] || return 0

    mkdir -p "$(dirname "${dest}")" >/dev/null 2>&1 || true

    # Flux volume browser operates on host paths and considers cross-mount
    # absolute symlinks as dangling. Ensure password files are regular files.
    if [[ -L "${dest}" ]]; then
      rm -f "${dest}" >/dev/null 2>&1 || true
    fi

    cp -f "${src}" "${dest}" >/dev/null 2>&1 || true
    chmod 644 "${dest}" >/dev/null 2>&1 || true
  }

  restore_password_files_from_sync() {
    # When SYNC_SAVES_ONLY=true, password files live in the synced folder
    # (SAVEGAMES_DIR) but the server reads/writes them in SAVED_DIR. Copy them
    # in before the server starts.
    for filename in Password.json PlayerPassword.json; do
      local sync_path="${password_root}/${filename}"
      local saved_path="${SAVED_DIR}/${filename}"

      if [[ -s "${sync_path}" ]]; then
        if is_true "${SR_FORCE_PASSWORD_FILES}" || [[ ! -s "${saved_path}" || "${sync_path}" -nt "${saved_path}" ]]; then
          sync_password_file "${sync_path}" "${saved_path}"
        fi
      fi
    done
  }

  export_password_files_to_install_dir() {
    # Keep a regular-file copy in the install dir (and server exe dir) to avoid
    # dangling symlinks when viewing Flux volumes.
    for filename in Password.json PlayerPassword.json; do
      local saved_path="${SAVED_DIR}/${filename}"
      [[ -s "${saved_path}" ]] || continue
      sync_password_file "${saved_path}" "${STEAM_INSTALL_DIR}/${filename}"
      if [[ -n "${server_exe_dir}" ]]; then
        sync_password_file "${saved_path}" "${server_exe_dir}/${filename}"
      fi
    done
  }

  restore_password_files_from_sync
  export_password_files_to_install_dir

  local g_drive="${WINE_G_DRIVE:-${SAVEGAMES_DIR}}"
  if [[ -z "${g_drive}" ]]; then
    g_drive="${SAVED_DIR}"
  fi
  mkdir -p "${WINEPREFIX}/dosdevices"
  ln -sfn "${g_drive}" "${WINEPREFIX}/dosdevices/g:"
}

remote_call_return() {
  local object_path="$1"
  local function_name="$2"
  shift 2

  python3 - "${object_path}" "${function_name}" "${SR_REMOTE_HOST}" "${SR_REMOTE_PORT}" "$@" <<'PY'
import json
import sys
import urllib.error
import urllib.request

object_path = sys.argv[1]
function_name = sys.argv[2]
host = sys.argv[3]
port = sys.argv[4]
kv_pairs = sys.argv[5:]

params = {}
for kv in kv_pairs:
    if "=" not in kv:
        continue
    k, v = kv.split("=", 1)
    params[k] = v

url = f"http://{host}:{port}/remote/object/call"

payload = {"objectPath": object_path, "functionName": function_name, "parameters": params}
data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(url, data=data, method="PUT", headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        body = resp.read().decode("utf-8", "replace")
except urllib.error.HTTPError as e:
    sys.stderr.write(e.read().decode("utf-8", "replace"))
    sys.exit(1)
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)

try:
    obj = json.loads(body)
except Exception:
    print(body)
    sys.exit(0)

err = ""
if isinstance(obj, dict):
    err = obj.get("errorMessage") or obj.get("ErrorMessage") or ""
if err:
    sys.stderr.write(str(err))
    sys.exit(1)

rv = obj.get("ReturnValue", "")
if isinstance(rv, (dict, list)):
    print(json.dumps(rv))
else:
    print(str(rv))
PY
}

tcp_listening_on_port() {
  local port="$1"
  local port_hex
  port_hex="$(printf '%04X' "${port}")"

  awk -v port_hex="${port_hex}" 'NR>1{split($2,a,":"); if (toupper(a[2])==port_hex && $4=="0A"){found=1}} END{exit found?0:1}' /proc/net/tcp 2>/dev/null \
    && return 0
  awk -v port_hex="${port_hex}" 'NR>1{split($2,a,":"); if (toupper(a[2])==port_hex && $4=="0A"){found=1}} END{exit found?0:1}' /proc/net/tcp6 2>/dev/null \
    && return 0
  return 1
}

udp_bound_on_port() {
  local port="$1"
  local port_hex
  port_hex="$(printf '%04X' "${port}")"

  awk -v port_hex="${port_hex}" 'NR>1{split($2,a,":"); if (toupper(a[2])==port_hex){found=1}} END{exit found?0:1}' /proc/net/udp 2>/dev/null \
    && return 0
  awk -v port_hex="${port_hex}" 'NR>1{split($2,a,":"); if (toupper(a[2])==port_hex){found=1}} END{exit found?0:1}' /proc/net/udp6 2>/dev/null \
    && return 0
  return 1
}

tail_saved_logs() {
  local dir="${SAVED_DIR}"
  [[ -d "${dir}" ]] || return 0

  local logs=""
  logs="$(find "${dir}" -maxdepth 4 -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 3 | cut -d' ' -f2- || true)"
  [[ -n "${logs}" ]] || return 0

  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    log "Saved log tail: ${f}"
    tail -n 80 "${f}" 2>/dev/null || true
  done <<<"${logs}"
}

timeout_diagnostics() {
  log "Diagnostics summary:"
  log "STEAM_INSTALL_DIR: ${STEAM_INSTALL_DIR}"
  log "WINEPREFIX: ${WINEPREFIX}"
  log "SYNC_SAVES_ONLY: ${SYNC_SAVES_ONLY}"
  log "SAVED_DIR: ${SAVED_DIR}"
  log "SAVEGAMES_DIR: ${SAVEGAMES_DIR}"

  local saved_link="${STEAM_INSTALL_DIR}/StarRupture/Saved"
  log "Saved symlink: ${saved_link}"
  ls -la "${saved_link}" 2>/dev/null || true

  log "Saved dir listing:"
  ls -la "${SAVED_DIR}" 2>/dev/null || true
  ls -la "${SAVED_DIR}/Logs" 2>/dev/null || true
  ls -la "${SAVED_DIR}/SaveGames" 2>/dev/null || true

  log "Processes (filtered):"
  ps auxww 2>/dev/null | grep -Ei 'StarRupture|wine|wineserver|Xvfb' | grep -v grep | head -n 50 || true

  tail_saved_logs || true
}

wait_for_remote_api() {
  local -a ports
  local ports_raw="${SR_REMOTE_PORTS:-}"
  if [[ -z "${ports_raw}" ]]; then
    ports_raw="${SR_REMOTE_PORT:-${SERVER_PORT}} 30010 30020"
  fi
  ports_raw="${ports_raw//,/ }"

  declare -A seen_ports=()
  local p=""
  for p in ${ports_raw}; do
    [[ "${p}" =~ ^[0-9]+$ ]] || continue
    if [[ -n "${seen_ports[${p}]:-}" ]]; then
      continue
    fi
    seen_ports["${p}"]=1
    ports+=("${p}")
  done
  if (( ${#ports[@]} == 0 )); then
    ports=("${SERVER_PORT}")
  fi

  local -a hosts
  hosts=("${SR_REMOTE_HOST}" "127.0.0.1" "localhost")

  local host_ips=""
  host_ips="$(hostname -I 2>/dev/null || true)"
  local hip=""
  for hip in ${host_ips}; do
    [[ "${hip}" == *:* ]] && continue
    [[ "${hip}" == 127.* ]] && continue
    hosts+=("${hip}")
  done

  local etc_hosts_ips=""
  etc_hosts_ips="$(awk '{print $1}' /etc/hosts 2>/dev/null | grep -E '^[0-9]+\\.' || true)"
  for hip in ${etc_hosts_ips}; do
    [[ "${hip}" == 127.* ]] && continue
    hosts+=("${hip}")
  done

  local i=0
  while (( i < SR_REMOTE_WAIT_SECS )); do
    if [[ -n "${SR_WINE_PID}" ]] && ! kill -0 "${SR_WINE_PID}" 2>/dev/null; then
      log "Server process exited while waiting for Remote Control API."
      return 1
    fi

    local h=""
    for h in "${hosts[@]}"; do
      [[ -n "${h}" ]] || continue
      local port=""
      for port in "${ports[@]}"; do
        local url="http://${h}:${port}/remote/info"
        if curl -fsS --connect-timeout 1 --max-time 2 "${url}" >/dev/null 2>&1; then
          SR_REMOTE_HOST="${h}"
          SR_REMOTE_PORT="${port}"
          return 0
        fi
      done
    done

    sleep 1
    i=$((i + 1))
  done

  log "Remote Control API not reachable after ${SR_REMOTE_WAIT_SECS}s; listener check:"
  local port=""
  for port in "${ports[@]}"; do
    if tcp_listening_on_port "${port}"; then
      log "TCP LISTEN: ${port} (yes)"
    else
      log "TCP LISTEN: ${port} (no)"
    fi
  done
  # For sanity, confirm the game ports are at least bound for UDP.
  if udp_bound_on_port "${SERVER_PORT}"; then
    log "UDP BOUND: ${SERVER_PORT} (yes)"
  else
    log "UDP BOUND: ${SERVER_PORT} (no)"
  fi
  if udp_bound_on_port "${QUERY_PORT}"; then
    log "UDP BOUND: ${QUERY_PORT} (yes)"
  else
    log "UDP BOUND: ${QUERY_PORT} (no)"
  fi

  timeout_diagnostics || true
  return 1
}

discover_settings_component() {
  local i
  for i in {0..9}; do
    local candidate="/Game/Chimera/Maps/DedicatedServerStart.DedicatedServerStart:PersistentLevel.BP_DedicatedServerSettingsActor_C_${i}.DedicatedServerSettingsComp"
    if remote_call_return "${candidate}" "IsPasswordSet" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

set_player_password_remote() {
  local settings_obj="$1"
  local token="$2"
  local password="$3"

  [[ -n "${password}" ]] || return 0

  local -a attempts=(
    "InPassword=${password}"
    "Password=${password}"
    "InPlayerPassword=${password}"
    "PlayerPassword=${password}"
    "InPassword=${password} InToken=${token}"
    "Password=${password} InToken=${token}"
    "InPlayerPassword=${password} InToken=${token}"
    "PlayerPassword=${password} InToken=${token}"
    "InPassword=${password} Token=${token}"
    "Password=${password} Token=${token}"
  )

  local args=""
  for args in "${attempts[@]}"; do
    # shellcheck disable=SC2206
    local -a kv=(${args})
    local rv=""
    if rv="$(remote_call_return "${settings_obj}" "SetPlayerPassword" "${kv[@]}" 2>/dev/null)"; then
      log "SetPlayerPassword succeeded."
      log "SetPlayerPassword returned: ${rv}"
      return 0
    fi
  done

  log "SetPlayerPassword failed (no compatible parameter signature)."
  return 1
}

wait_for_file_min_bytes() {
  local path="$1"
  local timeout="${2:-30}"
  local min_bytes="${3:-200}"

  [[ -n "${path}" ]] || return 1

  local start now size
  start="$(date +%s)"
  while true; do
    if [[ -s "${path}" ]]; then
      size="$(wc -c < "${path}" 2>/dev/null || echo 0)"
      if [[ "${size}" =~ ^[0-9]+$ ]] && (( size >= min_bytes )); then
        return 0
      fi
    fi
    now="$(date +%s)"
    if (( now - start >= timeout )); then
      return 1
    fi
    sleep 1
  done
}

looks_like_password_token() {
  local value="${1:-}"
  [[ -n "${value}" ]] || return 1
  [[ "${#value}" -eq 684 ]] || return 1
  [[ "${value}" =~ ^[A-Za-z0-9+/]+=$ ]] || return 1
  return 0
}

read_password_value_from_json() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  python3 - "${file}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r") as f:
        obj = json.load(f)
except Exception:
    sys.exit(1)

v = obj.get("Password", "")
if isinstance(v, str) and v:
    print(v)
    sys.exit(0)
sys.exit(1)
PY
}

password_file_has_token() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  local value=""
  value="$(read_password_value_from_json "${file}" 2>/dev/null || true)"
  looks_like_password_token "${value}"
}

copy_password_file_preserve() {
  local src="$1"
  local dest="$2"

  [[ -n "${src}" && -n "${dest}" ]] || return 0
  [[ -f "${src}" ]] || return 0

  mkdir -p "$(dirname "${dest}")" >/dev/null 2>&1 || true

  # Flux volume browser operates on host paths and considers cross-mount absolute
  # symlinks as dangling. Ensure password files are regular files.
  if [[ -L "${dest}" ]]; then
    rm -f "${dest}" >/dev/null 2>&1 || true
  fi

  cp -fp "${src}" "${dest}" >/dev/null 2>&1 || true
  chmod 644 "${dest}" >/dev/null 2>&1 || true
}

newest_password_token_file() {
  local filename="$1"
  local -a candidates=()

  candidates+=("${SAVED_DIR}/${filename}")
  if [[ -n "${SAVEGAMES_DIR:-}" ]]; then
    candidates+=("${SAVEGAMES_DIR}/${filename}")
  fi
  if [[ -n "${STEAM_INSTALL_DIR:-}" ]]; then
    candidates+=("${STEAM_INSTALL_DIR}/${filename}")
  fi
  if [[ -n "${SERVER_EXE:-}" ]]; then
    candidates+=("$(dirname "${SERVER_EXE}")/${filename}")
  fi

  local best=""
  local c=""
  for c in "${candidates[@]}"; do
    [[ -s "${c}" ]] || continue
    if password_file_has_token "${c}"; then
      if [[ -z "${best}" || "${c}" -nt "${best}" ]]; then
        best="${c}"
      fi
    fi
  done

  [[ -n "${best}" ]] || return 1
  printf '%s\n' "${best}"
}

sync_password_tokens_once() {
  local password_root="${SAVED_DIR}"
  if is_true "${SYNC_SAVES_ONLY}"; then
    password_root="${SAVEGAMES_DIR}"
  fi

  local server_exe_dir=""
  if [[ -n "${SERVER_EXE:-}" ]]; then
    server_exe_dir="$(dirname "${SERVER_EXE}")"
  fi

  local filename=""
  for filename in Password.json PlayerPassword.json; do
    local best=""
    best="$(newest_password_token_file "${filename}" 2>/dev/null || true)"
    [[ -n "${best}" ]] || continue

    local -a dests=()
    dests+=("${SAVED_DIR}/${filename}")
    if [[ -n "${password_root}" && "${password_root}" != "${SAVED_DIR}" ]]; then
      dests+=("${password_root}/${filename}")
    fi
    if [[ -n "${STEAM_INSTALL_DIR:-}" ]]; then
      dests+=("${STEAM_INSTALL_DIR}/${filename}")
    fi
    if [[ -n "${server_exe_dir}" ]]; then
      dests+=("${server_exe_dir}/${filename}")
    fi

    local dest=""
    for dest in "${dests[@]}"; do
      [[ "${dest}" == "${best}" ]] && continue
      if is_true "${SR_FORCE_PASSWORD_FILES}" || [[ ! -s "${dest}" || "${best}" -nt "${dest}" ]]; then
        copy_password_file_preserve "${best}" "${dest}"
      fi
    done
  done
}

start_password_token_sync_loop() {
  if ! is_true "${SYNC_SAVES_ONLY}"; then
    return
  fi

  local interval="${SR_PASSWORD_SYNC_INTERVAL_SECS:-10}"
  if [[ ! "${interval}" =~ ^[0-9]+$ ]] || (( interval <= 0 )); then
    return
  fi

  # Run once immediately to catch freshly-synced state.
  sync_password_tokens_once || true

  (
    while true; do
      sync_password_tokens_once || true
      sleep "${interval}"
    done
  ) &
}

persist_password_files_to_sync() {
  sync_password_tokens_once || true
}

auto_start_session() {
  if ! is_true "${SR_AUTO_START}"; then
    return
  fi

  if [[ -n "${SR_ADMIN_PASSWORD_TOKEN}" ]] && ! looks_like_password_token "${SR_ADMIN_PASSWORD_TOKEN}"; then
    log "Warning: SR_ADMIN_PASSWORD_TOKEN does not look like a password token (expected 684 base64 chars). Ignoring."
    SR_ADMIN_PASSWORD_TOKEN=""
  fi
  if [[ -n "${SR_PLAYER_PASSWORD_TOKEN}" ]] && ! looks_like_password_token "${SR_PLAYER_PASSWORD_TOKEN}"; then
    log "Warning: SR_PLAYER_PASSWORD_TOKEN does not look like a password token (expected 684 base64 chars). Ignoring."
    SR_PLAYER_PASSWORD_TOKEN=""
  fi

  SR_REMOTE_PORT="${SR_REMOTE_PORT:-${SERVER_PORT}}"

  if ! wait_for_remote_api; then
    log "Timed out waiting for Remote Control API (skipping auto-start)."
    return
  fi

  local settings_obj=""
  settings_obj="$(discover_settings_component 2>/dev/null || true)"
  if [[ -z "${settings_obj}" ]]; then
    log "Could not find DedicatedServerSettingsComp object (skipping auto-start)."
    return
  fi

  local saved_password_value=""
  saved_password_value="$(read_password_value_from_json "${SAVED_DIR}/Password.json" 2>/dev/null || true)"
  if [[ -n "${saved_password_value}" ]] && ! looks_like_password_token "${saved_password_value}"; then
    saved_password_value=""
  fi

  local saved_player_password_value=""
  saved_player_password_value="$(read_password_value_from_json "${SAVED_DIR}/PlayerPassword.json" 2>/dev/null || true)"
  if [[ -n "${saved_player_password_value}" ]] && ! looks_like_password_token "${saved_player_password_value}"; then
    saved_player_password_value=""
  fi

  local admin_secret=""
  if [[ -n "${SR_ADMIN_PASSWORD_TOKEN}" ]]; then
    admin_secret="${SR_ADMIN_PASSWORD_TOKEN}"
  elif [[ -n "${saved_password_value}" ]]; then
    admin_secret="${saved_password_value}"
    if [[ -n "${SR_ADMIN_PASSWORD}" ]]; then
      log "Note: Using existing Password.json token; SR_ADMIN_PASSWORD is ignored."
    fi
  else
    admin_secret="${SR_ADMIN_PASSWORD}"
    if [[ -n "${admin_secret}" ]]; then
      log "Warning: Using SR_ADMIN_PASSWORD as a plain string. StarRupture clients expect token-based passwords; Manage Server may not accept it."
    fi
  fi

  if [[ -z "${admin_secret}" ]]; then
    # On Flux failovers, Syncthing may populate the synced folder shortly after
    # the container starts. If we already have save data but no password token
    # yet, wait briefly for Password.json to appear before giving up.
    if is_true "${SYNC_SAVES_ONLY}" && [[ -n "${SAVEGAMES_DIR:-}" ]]; then
      if find "${SAVEGAMES_DIR}" -maxdepth 2 -type f \( -name '*.sav' -o -name 'SaveData.dat' \) 2>/dev/null | head -n 1 | grep -q .; then
        local wait_secs="${SR_CREDENTIALS_WAIT_SECS:-60}"
        log "No admin token yet; waiting up to ${wait_secs}s for synced Password.json..."
        local start now
        start="$(date +%s)"
        while true; do
          local candidate=""
          candidate="$(read_password_value_from_json "${SAVEGAMES_DIR}/Password.json" 2>/dev/null || true)"
          if [[ -n "${candidate}" ]] && looks_like_password_token "${candidate}"; then
            admin_secret="${candidate}"
            break
          fi
          now="$(date +%s)"
          if (( now - start >= wait_secs )); then
            break
          fi
          sleep 2
        done
      fi
    fi

    if [[ -z "${admin_secret}" ]]; then
      log "SR_AUTO_START=true but no admin password/token is available; skipping auto-start (use in-game Manage Server once to initialize)."
      return
    fi
  else
  local check_rv=""
  check_rv="$(remote_call_return "${settings_obj}" "CheckPassword" "InPassword=${admin_secret}" 2>/dev/null || true)"
  case "${check_rv}" in
    PASSWORDMATCHING:*|PASSWORDSET:*)
      ;;
    *)
      # The server may already have a different password set from a previous run.
      # To keep Flux deployments seamless and env-controlled, attempt to reset it
      # to SR_ADMIN_PASSWORD and retry.
      log "CheckPassword failed (will try to reset admin password and retry)."

      local set_rv=""
      set_rv="$(remote_call_return "${settings_obj}" "SetPassword" "InPassword=${admin_secret}" 2>/dev/null || true)"
      log "SetPassword returned: ${set_rv}"

      check_rv="$(remote_call_return "${settings_obj}" "CheckPassword" "InPassword=${admin_secret}" 2>/dev/null || true)"
      case "${check_rv}" in
        PASSWORDMATCHING:*|PASSWORDSET:*)
          ;;
        *)
          log "CheckPassword still failed after reset attempt (skipping auto-start)."
          return
          ;;
      esac
      ;;
  esac
  token="${check_rv#*:}"
  fi

  local player_secret=""
  if [[ -n "${SR_PLAYER_PASSWORD_TOKEN}" ]]; then
    player_secret="${SR_PLAYER_PASSWORD_TOKEN}"
  elif [[ -n "${saved_player_password_value}" ]]; then
    player_secret="${saved_player_password_value}"
    if [[ -n "${SR_PLAYER_PASSWORD}" ]]; then
      log "Note: Using existing PlayerPassword.json token; SR_PLAYER_PASSWORD is ignored."
    fi
  elif [[ -n "${SR_PLAYER_PASSWORD}" ]]; then
    player_secret="${SR_PLAYER_PASSWORD}"
    log "Warning: Using SR_PLAYER_PASSWORD as a plain string. StarRupture clients expect token-based passwords; join password may not be enforced."
  fi

  if [[ -n "${player_secret}" ]]; then
    set_player_password_remote "${settings_obj}" "${token}" "${player_secret}" || true
    if wait_for_file_min_bytes "${SAVED_DIR}/PlayerPassword.json" 30 200; then
      persist_password_files_to_sync || true
    fi
  fi
  if wait_for_file_min_bytes "${SAVED_DIR}/Password.json" 30 200; then
    persist_password_files_to_sync || true
  fi

  local savegames_root="${SAVED_DIR}/SaveGames"
  local session_to_load=""
  local save_base=""

  if readarray -t parsed < <(parse_save_data_file "${savegames_root}/SaveData.dat" 2>/dev/null); then
    session_to_load="${parsed[0]:-}"
    save_base="${parsed[1]:-}"
  fi

  local save_to_load=""
  if [[ -n "${session_to_load}" && -n "${save_base}" ]]; then
    save_to_load="${save_base}"
    if [[ "${save_to_load}" != *.sav ]]; then
      save_to_load="${save_to_load}.sav"
    fi
    if [[ ! -f "${savegames_root}/${session_to_load}/${save_to_load}" ]]; then
      session_to_load=""
      save_to_load=""
    fi
  fi

  if [[ -z "${session_to_load}" || -z "${save_to_load}" ]]; then
    local latest=""
    latest="$(latest_save_file_in_dir "${savegames_root}")"
    if [[ -n "${latest}" ]]; then
      session_to_load="$(basename "$(dirname "${latest}")")"
      save_to_load="$(basename "${latest}")"
    fi
  fi

  if [[ -n "${session_to_load}" && -n "${save_to_load}" ]]; then
    log "Auto-start: loading ${session_to_load}/${save_to_load}"
    local load_rv=""
    load_rv="$(remote_call_return "${settings_obj}" "LoadSessionSave" "InSessionName=${session_to_load}" "InSaveGameName=${save_to_load}" "InToken=${token}" 2>/dev/null || true)"
    log "LoadSessionSave returned: ${load_rv}"
    return
  fi

  local new_session="${SR_SESSION_NAME:-${SERVER_NAME}}"
  if [[ -z "${new_session}" ]]; then
    new_session="MyServer"
  fi

  log "Auto-start: no save found; starting new session ${new_session}"
  local new_rv=""
  new_rv="$(remote_call_return "${settings_obj}" "StartNewSession" "NewSessionName=${new_session}" "InToken=${token}" 2>/dev/null || true)"
  log "StartNewSession returned: ${new_rv}"
}

server_present=false
if [[ -n "${SERVER_EXE:-}" ]]; then
  [[ -f "${SERVER_EXE}" ]] && server_present=true
else
  detect_server_exe >/dev/null 2>&1 && server_present=true
fi

if is_true "${AUTO_UPDATE:-true}" || ! "${server_present}"; then
  harden_large_dirs_for_flux_browser
  disk_preflight
  steamcmd_update
  harden_large_dirs_for_flux_browser
else
  log "AUTO_UPDATE disabled and server executable exists; skipping SteamCMD update."
fi

resolve_server_exe

if [[ ! -f "${SERVER_EXE}" ]]; then
  log "Server executable not found at ${SERVER_EXE}"
  log "Listing install dir for troubleshooting:"
  ls -la "${STEAM_INSTALL_DIR}" || true
  exit 1
fi

if [[ -n "${ADMIN_PASSWORD_JSON:-}" ]]; then
  printf '%s\n' "${ADMIN_PASSWORD_JSON}" > "${STEAM_INSTALL_DIR}/Password.json"
  log "Wrote admin password file to ${STEAM_INSTALL_DIR}/Password.json"
fi

if [[ -n "${PLAYER_PASSWORD_JSON:-}" ]]; then
  printf '%s\n' "${PLAYER_PASSWORD_JSON}" > "${STEAM_INSTALL_DIR}/PlayerPassword.json"
  log "Wrote player password file to ${STEAM_INSTALL_DIR}/PlayerPassword.json"
fi

if [[ -d "${WINEPREFIX}" && "$(id -u)" -ne 0 ]]; then
  chown -R "$(id -u):$(id -g)" "${WINEPREFIX}" >/dev/null 2>&1 || true
fi

declare -a server_args
server_args=()

if is_true "${SR_LOG:-true}"; then
  server_args+=("-Log")
fi

if [[ -n "${SERVER_PORT}" ]]; then
  server_args+=("-Port=${SERVER_PORT}")
fi

if [[ -n "${QUERY_PORT}" ]]; then
  server_args+=("-QueryPort=${QUERY_PORT}")
fi

if [[ -n "${SERVER_NAME}" ]]; then
  server_args+=("-ServerName=${SERVER_NAME}")
fi

if [[ -n "${MULTIHOME}" ]]; then
  server_args+=("-MULTIHOME=${MULTIHOME}")
fi

if [[ -n "${SERVER_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  server_args+=(${SERVER_ARGS})
fi

log "Starting StarRupture dedicated server..."

if is_true "${USE_XVFB:-true}"; then
  XVFB_DISPLAY="${XVFB_DISPLAY:-99}"
  XVFB_ARGS="${XVFB_ARGS:--screen 0 1280x1024x24 -nolisten tcp -ac}"

  if ! command -v Xvfb >/dev/null 2>&1; then
    log "Xvfb not found but USE_XVFB=true"
    exit 1
  fi

  Xvfb ":${XVFB_DISPLAY}" ${XVFB_ARGS} &
  xvfb_pid=$!
  export DISPLAY=":${XVFB_DISPLAY}"

  trap 'kill -TERM ${xvfb_pid} >/dev/null 2>&1 || true' EXIT

  init_wine_prefix
  setup_persistence
  start_password_token_sync_loop

  cd "$(dirname "${SERVER_EXE}")"

  "${WINE_BIN}" "${SERVER_EXE}" "${server_args[@]}" &
  wine_pid=$!
  SR_WINE_PID="${wine_pid}"

  trap 'kill -TERM ${wine_pid} >/dev/null 2>&1 || true; kill -TERM ${xvfb_pid} >/dev/null 2>&1 || true' SIGTERM SIGINT

  auto_start_session || true

  wait "${wine_pid}"
  exit $?
else
  init_wine_prefix
  setup_persistence
  start_password_token_sync_loop
  cd "$(dirname "${SERVER_EXE}")"
  "${WINE_BIN}" "${SERVER_EXE}" "${server_args[@]}" &
  wine_pid=$!
  SR_WINE_PID="${wine_pid}"
  trap 'kill -TERM ${wine_pid} >/dev/null 2>&1 || true' SIGTERM SIGINT
  auto_start_session || true
  wait "${wine_pid}"
fi
