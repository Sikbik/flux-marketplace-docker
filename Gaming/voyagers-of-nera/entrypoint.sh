#!/bin/bash
set -e

SERVER_DIR="/home/steam/nera/server"
STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
APP_ID="3937860"

WINEPREFIX="${WINEPREFIX:-/home/steam/.wine}"
WINEARCH="${WINEARCH:-win64}"
if [ -z "${WINEDLLOVERRIDES:-}" ]; then
    WINEDLLOVERRIDES="mscoree,mshtml="
fi
export WINEPREFIX WINEARCH WINEDLLOVERRIDES

echo "=========================================="
echo "  Voyagers of Nera Dedicated Server"
echo "  (Wine)"
echo "=========================================="

# Update user/group IDs if provided
if [ -n "${PUID}" ] && [ "${PUID}" != "1000" ]; then
    echo "Updating UID to ${PUID}..."
    usermod -u ${PUID} steam
fi

if [ -n "${PGID}" ] && [ "${PGID}" != "1000" ]; then
    echo "Updating GID to ${PGID}..."
    groupmod -g ${PGID} steam
fi

# Ensure proper ownership
chown -R steam:steam /home/steam

# Clean up stale X lock files and start virtual framebuffer
echo "Starting virtual display..."
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
Xvfb :99 -screen 0 1024x768x16 &
sleep 2

# Function to run commands as steam user
run_as_steam() {
    gosu steam "$@"
}

mkdir -p "${WINEPREFIX}"
chown -R steam:steam "${WINEPREFIX}"

if [ ! -d "${WINEPREFIX}/drive_c" ]; then
    echo "Initializing Wine prefix (this may take a few minutes)..."
    run_as_steam env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES}" wineboot -u 2>&1 || true
    sleep 5
    echo "Wine prefix initialized."
fi

if [ -n "${WINE_TRICKS:-}" ]; then
    if command -v winetricks >/dev/null 2>&1; then
        TRICKS_MARKER="${WINEPREFIX}/.winetricks_done"
        if [ ! -f "${TRICKS_MARKER}" ]; then
            echo "Installing winetricks packages: ${WINE_TRICKS}"
            run_as_steam env WINEPREFIX="${WINEPREFIX}" WINEARCH="${WINEARCH}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES}" winetricks -q ${WINE_TRICKS} 2>&1 || true
            touch "${TRICKS_MARKER}"
            chown steam:steam "${TRICKS_MARKER}"
        fi
    else
        echo "WARNING: WINE_TRICKS is set but winetricks is not installed."
    fi
fi

# Ensure server directory exists
mkdir -p ${SERVER_DIR}
chown -R steam:steam ${SERVER_DIR}

# Download/Update server via SteamCMD
echo "Checking for server updates..."
run_as_steam ${STEAMCMD} \
    +force_install_dir ${SERVER_DIR} \
    +login anonymous \
    +@sSteamCmdForcePlatformType windows \
    +app_update ${APP_ID} validate \
    +quit

# Ensure save directory exists and is writable
SAVE_DIR="${SERVER_DIR}/BoatGame/Saved"
CONFIG_DIR="${SAVE_DIR}/Config/WindowsServer"
PERSIST_DIR="${SAVE_DIR}/PersistedData"
CUSTOM_CONFIG_DIR="${PERSIST_DIR}/CustomConfig"
mkdir -p "${CONFIG_DIR}"
mkdir -p "${PERSIST_DIR}"
mkdir -p "${CUSTOM_CONFIG_DIR}"

# Optionally clear Engine.ini to return to defaults (keeps a backup).
ENGINE_INI="${CONFIG_DIR}/Engine.ini"
if [ "${CLEAR_ENGINE_INI:-false}" = "true" ] && [ -f "${ENGINE_INI}" ]; then
    BACKUP_SUFFIX="$(date +%s)"
    BACKUP_PATH="${ENGINE_INI}.bak.${BACKUP_SUFFIX}"
    echo "Clearing Engine.ini override (backup: ${BACKUP_PATH})"
    mv "${ENGINE_INI}" "${BACKUP_PATH}"
fi

# Optionally clear custom host/game config so the server can regenerate defaults.
CUSTOM_HOST_INI="${CUSTOM_CONFIG_DIR}/CustomHostServerUserSettings.ini"
CUSTOM_GAME_INI="${CUSTOM_CONFIG_DIR}/CustomGameUserSettings.ini"
LEGACY_HOST_INI="${CONFIG_DIR}/CustomHostServerUserSettings.ini"
LEGACY_GAME_INI="${CONFIG_DIR}/CustomGameUserSettings.ini"
if [ "${CLEAR_CUSTOM_CONFIGS:-false}" = "true" ]; then
    BACKUP_SUFFIX="$(date +%s)"
    for path in "${CUSTOM_HOST_INI}" "${CUSTOM_GAME_INI}" "${LEGACY_HOST_INI}" "${LEGACY_GAME_INI}"; do
        if [ -f "${path}" ]; then
            BACKUP_PATH="${path}.bak.${BACKUP_SUFFIX}"
            echo "Clearing $(basename "${path}") (backup: ${BACKUP_PATH})"
            mv "${path}" "${BACKUP_PATH}"
        fi
    done
fi

# Generate CustomHostServerUserSettings.ini
if [ "${MANAGE_CONFIG:-true}" = "true" ]; then
    echo "Generating server configuration..."
    for path in "${CUSTOM_HOST_INI}" "${LEGACY_HOST_INI}"; do
        cat > "${path}" << EOF
[/Script/BoatGame.BGCustomHostServerSettings]
HostServerDisplayName=${HOST_SERVER_DISPLAY_NAME:-Voyagers of Nera Server}
HostServerPassword=${HOST_SERVER_PASSWORD:-}
MaxPlayers=${MAX_PLAYERS:-10}
AutosaveTimerSeconds=${AUTOSAVE_TIMER_SECONDS:-300}
EOF
    done

# Generate CustomGameUserSettings.ini
    for path in "${CUSTOM_GAME_INI}" "${LEGACY_GAME_INI}"; do
        cat > "${path}" << EOF
[/Script/BoatGame.BGCustomGameSettings]
GatheringRateMultiplier=${GATHERING_RATE_MULTIPLIER:-1.0}
EnemyDamageMultiplier=${ENEMY_DAMAGE_MULTIPLIER:-1.0}
PlayerDamageMultiplier=${PLAYER_DAMAGE_MULTIPLIER:-1.0}
DisableEquipmentDurability=${DISABLE_EQUIPMENT_DURABILITY:-False}
DisableDropItemsOnDeath=${DISABLE_DROP_ITEMS_ON_DEATH:-False}
EOF
    done

    echo "Configuration files generated:"
    echo "  - CustomHostServerUserSettings.ini (CustomConfig + WindowsServer)"
    echo "  - CustomGameUserSettings.ini (CustomConfig + WindowsServer)"
else
    echo "Skipping config generation (MANAGE_CONFIG=false)."
fi

# Set ownership of config files
chown -R steam:steam "${SAVE_DIR}"

# Optionally override the online subsystem (writes Engine.ini when set)
if [ -n "${ONLINE_SUBSYSTEM:-}" ]; then
    echo "Configuring online subsystem: ${ONLINE_SUBSYSTEM}"
    cat > "${ENGINE_INI}" << EOF
[OnlineSubsystem]
DefaultPlatformService=${ONLINE_SUBSYSTEM}
EOF
    if [ "${ONLINE_SUBSYSTEM}" = "Steam" ]; then
        cat >> "${ENGINE_INI}" << EOF

[OnlineSubsystemSteam]
bEnabled=true
EOF
    fi
    chown steam:steam "${ENGINE_INI}"
fi

# Optionally override EOS DeploymentId (align server with client deployment).
if [ -n "${EOS_DEPLOYMENT_ID:-}" ]; then
    echo "Overriding EOS DeploymentId: ${EOS_DEPLOYMENT_ID}"
    cat >> "${ENGINE_INI}" << EOF

[EpicOnlineServices]
DeploymentId=${EOS_DEPLOYMENT_ID}
EOF
    chown steam:steam "${ENGINE_INI}"
fi

# Optionally disable presence advertising / lobbies (best-effort).
if [ "${DISABLE_PRESENCE:-false}" = "true" ]; then
    echo "Disabling presence/lobby advertising (best-effort)."
    cat >> "${ENGINE_INI}" << EOF

[/Script/CommonUser.CommonSessionSubsystem]
bUsesPresence=false
bShouldAdvertise=true
bAllowJoinViaPresence=false
bAllowJoinViaPresenceFriendsOnly=false
bUseLobbiesIfAvailable=false
bUseLobbies=false

[OnlineSubsystemEOS]
bUseLobbiesIfAvailable=false
bUseLobbies=false
bUsesPresence=false

[OnlineSubsystemRedpointEOS]
bUseLobbiesIfAvailable=false
bUseLobbies=false
bUsesPresence=false

[EpicOnlineServices]
PresenceAdvertises=None
EOF
    chown steam:steam "${ENGINE_INI}"
fi

# Build server arguments
SERVER_ARGS="-log"

if [ "${ENABLE_LOGGING}" = "true" ]; then
    SERVER_ARGS="${SERVER_ARGS} -LoggingInShippingEnabled=true"
fi

if [ "${DISABLE_STEAM:-false}" = "true" ]; then
    SERVER_ARGS="${SERVER_ARGS} -NOSTEAM"
fi

if [ "${ONLINE_SUBSYSTEM:-}" = "Steam" ] && [ "${DISABLE_STEAM:-false}" = "true" ]; then
    echo "WARNING: ONLINE_SUBSYSTEM=Steam but DISABLE_STEAM=true; Steam services are disabled."
fi

if [ -n "${SERVER_PORT}" ] && [ "${SERVER_PORT}" != "7777" ]; then
    SERVER_ARGS="${SERVER_ARGS} -port=${SERVER_PORT}"
fi

if [ -n "${QUERY_PORT:-}" ]; then
    SERVER_ARGS="${SERVER_ARGS} -QueryPort=${QUERY_PORT}"
fi

# Export EOS_OVERRIDE_HOST_IP if set
if [ -n "${EOS_OVERRIDE_HOST_IP}" ]; then
    echo "Setting host IP override to: ${EOS_OVERRIDE_HOST_IP}"
    export EOS_OVERRIDE_HOST_IP="${EOS_OVERRIDE_HOST_IP}"
fi

# Prefer the launcher EXE to match official docs; allow forcing shipping.
USE_STUB_EXE="${USE_STUB_EXE:-false}"
SERVER_EXE_SHIPPING="${SERVER_DIR}/BoatGame/Binaries/Win64/BoatGameServer-Win64-Shipping.exe"
SERVER_EXE_LAUNCHER="${SERVER_DIR}/BoatGameServer.exe"
if [ "${USE_STUB_EXE}" = "true" ] && [ -f "${SERVER_EXE_LAUNCHER}" ]; then
    SERVER_EXE="${SERVER_EXE_LAUNCHER}"
else
    SERVER_EXE="${SERVER_EXE_SHIPPING}"
    if [ ! -f "${SERVER_EXE}" ] && [ -f "${SERVER_EXE_LAUNCHER}" ]; then
        SERVER_EXE="${SERVER_EXE_LAUNCHER}"
    fi
fi

if [ ! -f "${SERVER_EXE}" ]; then
    echo "ERROR: Server executable not found!"
    echo "Contents of server directory:"
    ls -la "${SERVER_DIR}"
    exit 1
fi

echo "=========================================="
echo "  Starting server..."
echo "  Server Name: ${HOST_SERVER_DISPLAY_NAME:-Voyagers of Nera Server}"
echo "  Port: ${SERVER_PORT:-7777}"
echo "  Query Port: ${QUERY_PORT:-auto}"
echo "  Online Subsystem: ${ONLINE_SUBSYSTEM:-auto}"
echo "  Max Players: ${MAX_PLAYERS:-10}"
echo "  Host IP Override: ${EOS_OVERRIDE_HOST_IP:-auto}"
echo "  Autosave: ${AUTOSAVE_TIMER_SECONDS:-300}s"
echo "  Gathering Rate: ${GATHERING_RATE_MULTIPLIER:-1.0}x"
echo "  Enemy Damage: ${ENEMY_DAMAGE_MULTIPLIER:-1.0}x"
echo "  Player Damage: ${PLAYER_DAMAGE_MULTIPLIER:-1.0}x"
echo "  Disable Durability: ${DISABLE_EQUIPMENT_DURABILITY:-False}"
echo "  Keep Items on Death: ${DISABLE_DROP_ITEMS_ON_DEATH:-False}"
echo "=========================================="

# Run the server via Wine
cd "${SERVER_DIR}"
echo "Executable: ${SERVER_EXE}"
echo "Arguments: ${SERVER_ARGS}"
echo "Launching via Wine..."

# Ensure Steam App ID is visible to the game.
LOG_DIR="${SERVER_DIR}/BoatGame/Saved/Logs"
SERVER_EXE_DIR="$(dirname "${SERVER_EXE}")"
mkdir -p "${LOG_DIR}"
echo "${APP_ID}" > "${SERVER_DIR}/steam_appid.txt"
echo "${APP_ID}" > "${SERVER_EXE_DIR}/steam_appid.txt"
chown steam:steam "${SERVER_DIR}/steam_appid.txt" "${SERVER_EXE_DIR}/steam_appid.txt" "${LOG_DIR}"

# Copy Steam runtime DLLs next to the server EXE so Steam API can initialize.
for dll in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
    if [ -f "${SERVER_DIR}/${dll}" ] && [ ! -f "${SERVER_EXE_DIR}/${dll}" ]; then
        cp "${SERVER_DIR}/${dll}" "${SERVER_EXE_DIR}/${dll}"
        chown steam:steam "${SERVER_EXE_DIR}/${dll}"
    fi
done

WINE_BIN="wine64"
if ! command -v "${WINE_BIN}" >/dev/null 2>&1; then
    WINE_BIN="wine"
fi
gosu steam env \
    WINEPREFIX="${WINEPREFIX}" \
    WINEARCH="${WINEARCH}" \
    WINEDEBUG="${WINEDEBUG:-}" \
    WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}" \
    STEAM_APPID="${APP_ID}" \
    STEAM_GAMEID="${APP_ID}" \
    SteamAppId="${APP_ID}" \
    SteamGameId="${APP_ID}" \
    "${WINE_BIN}" "${SERVER_EXE}" ${SERVER_ARGS} 2>&1 &
SERVER_PID=$!
sleep 10

# Check if process is running
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server process started (PID: $SERVER_PID)"
else
    echo "ERROR: Server process died!"
fi

# Check for any log files
echo "Checking for log files..."
ls -la "${SERVER_DIR}/BoatGame/Saved/" 2>/dev/null || echo "Saved directory doesn't exist yet"
ls -la "${SERVER_DIR}/BoatGame/Saved/Logs/" 2>/dev/null || echo "Logs directory doesn't exist yet"

# Wait a bit more for logs to appear
sleep 20

# Check again
echo "Checking again after 20s..."
ls -la "${SERVER_DIR}/BoatGame/Saved/Logs/" 2>/dev/null || echo "Still no Logs directory"

# Check if process is still running
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server still running (PID: $SERVER_PID)"
else
    echo "Server process died!"
fi

# Tail UE log files if they exist
UE_LOG="${SERVER_DIR}/BoatGame/Saved/Logs/BoatGameServer.log"
if [ -f "$UE_LOG" ]; then
    echo "=== UE Server Log ==="
    tail -f "$UE_LOG" &
else
    # Try to find any .log files
    echo "Looking for any log files..."
    find "${SERVER_DIR}" -name "*.log" -type f 2>/dev/null | head -10
fi

# Keep container running and wait for server
wait $SERVER_PID
