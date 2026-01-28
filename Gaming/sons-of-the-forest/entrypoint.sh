#!/bin/bash
set -euo pipefail

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
STEAM_APP_ID="${STEAM_APP_ID:-2465200}"
STEAM_INSTALL_DIR="${STEAM_INSTALL_DIR:-/data/server}"
SOTF_USERDATA_PATH="${SOTF_USERDATA_PATH:-/config}"

WINEPREFIX="${WINEPREFIX:-/data/wine/prefix}"
WINEARCH="${WINEARCH:-win64}"
WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

echo "=========================================="
echo "  Sons of the Forest Dedicated Server"
echo "  (SteamCMD + Wine, Flux-friendly)"
echo "=========================================="
echo "Steam AppID: ${STEAM_APP_ID}"
echo "Install dir: ${STEAM_INSTALL_DIR}"
echo "User data:   ${SOTF_USERDATA_PATH}"
echo "Wine prefix: ${WINEPREFIX}"

run_as_steam() {
  gosu steam "$@"
}

id_changed="false"
if [[ -n "${PUID:-}" ]] && [[ "${PUID}" != "1000" ]]; then
  echo "Updating UID to ${PUID}..."
  if usermod -u "${PUID}" steam; then
    id_changed="true"
  fi
fi

if [[ -n "${PGID:-}" ]] && [[ "${PGID}" != "1000" ]]; then
  echo "Updating GID to ${PGID}..."
  if groupmod -g "${PGID}" steam; then
    id_changed="true"
  fi
fi

mkdir -p "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")"
if [[ "${id_changed}" == "true" ]]; then
  chown -R steam:steam "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
else
  chown steam:steam "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true
fi
chmod 755 "${STEAM_INSTALL_DIR}" "${SOTF_USERDATA_PATH}" "$(dirname "${WINEPREFIX}")" >/dev/null 2>&1 || true

mkdir -p "${WINEPREFIX}"
chown -R steam:steam "${WINEPREFIX}" >/dev/null 2>&1 || true

if [[ "${USE_XVFB:-true}" == "true" ]]; then
  echo "Starting virtual display (Xvfb)..."
  rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
  Xvfb :99 -screen 0 1024x768x16 &
  sleep 2
fi

if [[ ! -d "${WINEPREFIX}/drive_c" ]]; then
  echo "Initializing Wine prefix (first boot; may take a few minutes)..."
  run_as_steam env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES}" wineboot -u 2>&1 || true
  sleep 5
  echo "Wine prefix initialized."
fi

steamcmd_update() {
  if [[ "${AUTO_UPDATE:-true}" != "true" ]]; then
    echo "AUTO_UPDATE=false; skipping SteamCMD update."
    return 0
  fi

  echo "Checking for server updates via SteamCMD..."

  local args=(
    +force_install_dir "${STEAM_INSTALL_DIR}"
  )

  if [[ "${STEAM_LOGIN:-anonymous}" == "anonymous" ]]; then
    args+=(+login anonymous)
  else
    args+=(+login "${STEAM_LOGIN}" "${STEAM_PASSWORD:-}" "${STEAM_GUARD:-}")
  fi

  args+=(+app_update "${STEAM_APP_ID}")

  if [[ "${STEAMCMD_VALIDATE:-true}" == "true" ]]; then
    args+=(validate)
  fi

  args+=(+quit)

  local rc=0
  set +e
  run_as_steam "${STEAMCMD}" "${args[@]}"
  rc=$?
  set -e

  if (( rc == 0 )); then
    return 0
  fi

  echo "SteamCMD failed (rc=${rc}); retrying once after recursive chown..."
  chown -R steam:steam "${STEAM_INSTALL_DIR}" /home/steam 2>/dev/null || true

  set +e
  run_as_steam "${STEAMCMD}" "${args[@]}"
  rc=$?
  set -e

  return "${rc}"
}

steamcmd_update

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

CONFIG_FILE="${SOTF_USERDATA_PATH}/dedicatedserver.cfg"
OWNERS_FILE="${SOTF_USERDATA_PATH}/ownerswhitelist.txt"

if [[ "${MANAGE_CONFIG:-true}" == "true" ]]; then
  echo "Generating ${CONFIG_FILE} (MANAGE_CONFIG=true)..."

  ip="$(json_escape "${SOTF_IP_ADDRESS:-0.0.0.0}")"
  server_name="$(json_escape "${SOTF_SERVER_NAME:-flux}")"
  password="$(json_escape "${SOTF_PASSWORD:-}")"

  lan_only="${SOTF_LAN_ONLY:-false}"
  skip_test="${SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST:-true}"

  cat > "${CONFIG_FILE}" <<EOF
{
  "IpAddress": "${ip}",
  "GamePort": ${SOTF_GAME_PORT:-8766},
  "QueryPort": ${SOTF_QUERY_PORT:-27016},
  "BlobSyncPort": ${SOTF_BLOB_SYNC_PORT:-9700},
  "ServerName": "${server_name}",
  "MaxPlayers": ${SOTF_MAX_PLAYERS:-8},
  "Password": "${password}",
  "LanOnly": ${lan_only},
  "SaveSlot": ${SOTF_SAVE_SLOT:-1},
  "SaveMode": "${SOTF_SAVE_MODE:-Continue}",
  "GameMode": "${SOTF_GAME_MODE:-Normal}",
  "SaveInterval": ${SOTF_SAVE_INTERVAL:-600},
  "LogFilesEnabled": true,
  "TimestampLogFilenames": true,
  "TimestampLogEntries": true,
  "SkipNetworkAccessibilityTest": ${skip_test},
  "GameSettings": {},
  "CustomGameModeSettings": {}
}
EOF

  chown steam:steam "${CONFIG_FILE}" >/dev/null 2>&1 || true
fi

if [[ ! -f "${OWNERS_FILE}" ]]; then
  cat > "${OWNERS_FILE}" <<'EOF'
# ownerswhitelist.txt
# Put one SteamID64 per line. Example:
# 76561198000000000
EOF
  chown steam:steam "${OWNERS_FILE}" >/dev/null 2>&1 || true
fi

if [[ -n "${SOTF_OWNERS:-}" ]]; then
  echo "Writing owners list from SOTF_OWNERS..."
  {
    echo "# ownerswhitelist.txt (generated from SOTF_OWNERS)"
    echo "${SOTF_OWNERS}" | tr ', ' '\n' | sed '/^$/d'
  } > "${OWNERS_FILE}"
  chown steam:steam "${OWNERS_FILE}" >/dev/null 2>&1 || true
fi

SERVER_EXE="${SOTF_SERVER_EXE:-${STEAM_INSTALL_DIR}/SonsOfTheForestDS.exe}"
if [[ ! -f "${SERVER_EXE}" ]]; then
  echo "ERROR: Server EXE not found at ${SERVER_EXE}"
  echo "Contents of install dir:"
  ls -la "${STEAM_INSTALL_DIR}" || true
  exit 1
fi

echo "Launching server..."
echo "Config: ${CONFIG_FILE}"
echo "Owners: ${OWNERS_FILE}"
echo "Args:   -batchmode -nographics -userdatapath ${SOTF_USERDATA_PATH} ${SOTF_SERVER_ARGS:-}"

WINE_BIN="wine64"
if ! command -v "${WINE_BIN}" >/dev/null 2>&1; then
  WINE_BIN="wine"
fi

cd "${STEAM_INSTALL_DIR}"
exec gosu steam env \
  DISPLAY="${DISPLAY:-:99}" \
  WINEPREFIX="${WINEPREFIX}" \
  WINEARCH="${WINEARCH}" \
  WINEDEBUG="${WINEDEBUG:-}" \
  WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
  "${WINE_BIN}" "${SERVER_EXE}" \
    -batchmode \
    -nographics \
    -userdatapath "${SOTF_USERDATA_PATH}" \
    ${SOTF_SERVER_ARGS:-}
