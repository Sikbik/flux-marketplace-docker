# Sons of the Forest Dedicated Server (Flux-friendly)
# - Uses SteamCMD to install/update the dedicated server (appid 2465200)
# - Runs the Windows-only server under Wine with Xvfb
FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.title="Sons of the Forest Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="SteamCMD + Wine wrapper for Sons of the Forest Dedicated Server, designed for Flux volumes."

ENV DEBIAN_FRONTEND=noninteractive

# SteamCMD
ENV STEAM_APP_ID=2465200 \
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
    MIN_FREE_GB=30 \
    HARDEN_FLUX_VOLUME_BROWSER=false

# Flux-friendly persistence paths
# - /data: local cache (Steam install + Wine prefix) (recommended on Flux via a non-synced volume)
# - /config: synced config + saves (recommended on Flux via g:/)
ENV SOTF_USERDATA_PATH=/config

# Config generation (set MANAGE_CONFIG=false to manage dedicatedserver.cfg yourself)
ENV MANAGE_CONFIG=true \
    SOTF_CONFIG_APPLY_MODE=always \
    SOTF_OWNERS_APPLY_MODE=always \
    SOTF_IP_ADDRESS=0.0.0.0 \
    SOTF_GAME_PORT=8766 \
    SOTF_QUERY_PORT=27016 \
    SOTF_BLOB_SYNC_PORT=9700 \
    SOTF_SERVER_NAME=flux \
    SOTF_MAX_PLAYERS=8 \
    SOTF_PASSWORD= \
    SOTF_LAN_ONLY=false \
    SOTF_SAVE_SLOT=1 \
    SOTF_SAVE_MODE=Continue \
    SOTF_GAME_MODE=Normal \
    SOTF_SAVE_INTERVAL=600 \
    SOTF_IDLE_DAY_CYCLE_SPEED=0.0 \
    SOTF_IDLE_TARGET_FRAMERATE=5 \
    SOTF_ACTIVE_TARGET_FRAMERATE=60 \
    SOTF_LOG_FILES_ENABLED=true \
    SOTF_TIMESTAMP_LOG_FILENAMES=true \
    SOTF_TIMESTAMP_LOG_ENTRIES=true \
    SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST=true

# Wine
ENV WINEPREFIX=/data/wine/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    USE_XVFB=true \
    XVFB_DISPLAY=99 \
    XVFB_ARGS="-screen 0 1024x768x24 -nolisten tcp -ac" \
    HOME=/home/steam \
    USER=steam

# Dedicated server runtime behavior
# The official StartSOTFDedicated.bat writes steam_appid.txt with the base game appid (1326470).
ENV SOTF_WRITE_STEAM_APPID_TXT=true \
    SOTF_STEAM_APP_ID=1326470 \
    SOTF_STEAM_GAME_ID=1326470 \
    SOTF_VERBOSE_LOGGING=false

RUN dpkg --add-architecture i386 \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     gosu \
     gnupg \
     procps \
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

RUN mkdir -p /data /config /home/steam/sotf \
  && chown -R steam:steam /data /config /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /home/steam/sotf

# Common ports (game + query + blob sync). Protocol usage can vary by host/network;
# map UDP at minimum.
EXPOSE 8766/udp 27016/udp 9700/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
