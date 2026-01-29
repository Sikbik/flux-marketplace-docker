# V Rising Dedicated Server (Flux-friendly)
# - Uses SteamCMD to install/update the dedicated server (Steam tool appid 1829350)
# - Runs the Windows-only server under Wine with Xvfb
FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.title="V Rising Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="SteamCMD + Wine wrapper for V Rising Dedicated Server, designed for Flux volumes."

ENV DEBIAN_FRONTEND=noninteractive

# SteamCMD
ENV STEAM_APP_ID=1829350 \
    STEAM_INSTALL_DIR=/data/server \
    STEAM_LOGIN=anonymous \
    STEAM_PASSWORD= \
    STEAM_GUARD= \
    STEAM_BRANCH= \
    STEAM_BRANCH_PASSWORD= \
    STEAMCMD_FORCE_PLATFORM_TYPE=windows \
    STEAMCMD_EXTRA_ARGS= \
    STEAMCMD_HOME=/data/steam \
    STEAMCMD_LOG_FILE=/data/steam/steamcmd.log \
    STEAMCMD_RESET_ON_MISSING_CONFIG=true \
    STEAMCMD_RETRY_NO_VALIDATE_ON_FAIL=true \
    STEAMCMD_VALIDATE=true \
    AUTO_UPDATE=true \
    DISK_PREFLIGHT=true \
    MIN_FREE_GB=15 \
    HARDEN_FLUX_VOLUME_BROWSER=false

# Flux-friendly persistence paths
# - /data: local cache (Steam install + SteamCMD cache) (recommended on Flux via a non-synced volume)
# - /config: synced config + saves (recommended on Flux via g:/)
ENV VR_PERSISTENT_DATA_DIR=/config/save-data

# Config management
ENV MANAGE_CONFIG=true \
    VR_CONFIG_APPLY_MODE=always \
    VR_LISTS_APPLY_MODE=always

# Player-facing settings (written into ServerHostSettings.json)
ENV VR_SERVER_NAME="RunOnFlux - V Rising" \
    VR_SERVER_DESCRIPTION= \
    VR_SAVE_NAME=RunOnFlux \
    VR_PASSWORD= \
    VR_GAME_PORT=9876 \
    VR_QUERY_PORT=9877 \
    VR_MAX_PLAYERS=40 \
    VR_MAX_ADMINS=4 \
    VR_SERVER_FPS=30 \
    VR_SECURE=true \
    VR_LIST_ON_STEAM=true \
    VR_LIST_ON_EOS=true \
    VR_AUTOSAVE_INTERVAL=600 \
    VR_AUTOSAVE_COUNT=50 \
    VR_GAME_SETTINGS_PRESET=

# Optional RCON (port must be opened by your platform)
ENV VR_RCON_ENABLED=false \
    VR_RCON_PORT=25575 \
    VR_RCON_PASSWORD=

# Optional: provide full JSON to overwrite ServerGameSettings.json
ENV VR_GAME_SETTINGS_JSON= \
    VR_GAME_SETTINGS_JSON_B64=

# Optional: admin / whitelist / banlist (one SteamID64 per line; commas accepted)
ENV VR_ADMIN_LIST= \
    VR_WHITELIST= \
    VR_BANLIST=

# Wine
#
# NOTE: The Wine prefix contains a very large number of small files. On Flux,
# the volume explorer can struggle when browsing large directory trees on app
# volumes. We therefore default the Wine prefix to the container rootfs (/opt)
# instead of the Flux volume (/data). You can override WINEPREFIX to persist it.
ENV WINEPREFIX=/opt/wine/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    USE_XVFB=true \
    XVFB_DISPLAY=99 \
    XVFB_ARGS="-screen 0 1024x768x24 -nolisten tcp -ac" \
    HOME=/home/steam \
    USER=steam

# Dedicated server runtime behavior
ENV VR_WRITE_STEAM_APPID_TXT=true \
    VR_BASE_GAME_APP_ID=1604030 \
    VR_SERVER_ARGS= \
    VR_LOG_FILE=

RUN dpkg --add-architecture i386 \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     gosu \
     gnupg \
     procps \
     python3 \
     wget \
     winbind \
     xvfb \
  && mkdir -p /etc/apt/keyrings \
  && wget -qO /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key \
  && gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key /tmp/winehq.key \
  && rm -f /tmp/winehq.key \
  && wget -qO /etc/apt/sources.list.d/winehq.sources https://dl.winehq.org/wine-builds/debian/dists/trixie/winehq-trixie.sources \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     winehq-staging \
  && apt-get purge -y --auto-remove \
     gnupg \
     wget \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /config /home/steam/vrising \
  && chown -R steam:steam /data /config /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /home/steam/vrising

# Common ports: game + query are UDP. RCON is TCP (optional).
EXPOSE 9876/udp 9877/udp 25575/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]

