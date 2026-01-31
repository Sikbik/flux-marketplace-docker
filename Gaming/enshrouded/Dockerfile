# Enshrouded Dedicated Server (Flux-friendly)
# - Windows-only dedicated server runs under Wine
# - Uses SteamCMD to install/update the server
FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.title="Enshrouded Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="SteamCMD + Wine wrapper for Enshrouded Dedicated Server, designed for Flux volumes."

ENV DEBIAN_FRONTEND=noninteractive

# SteamCMD / install
ENV STEAM_APP_ID=2278520 \
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
    HARDEN_FLUX_VOLUME_BROWSER=true

# Flux-friendly persistence paths
# - /data: local cache (Steam install + SteamCMD cache) (recommended on Flux via a non-synced volume)
# - /config: synced config + saves (recommended on Flux via g:/)
ENV ENS_CONFIG_DIR=/config \
    ENS_SAVE_DIR=/config/savegame \
    ENS_LOG_DIR=/config/logs

# Config management (enshrouded_server.json)
ENV MANAGE_CONFIG=true \
    ENS_CONFIG_APPLY_MODE=always

# Player-facing settings
ENV ENS_SERVER_NAME="RunOnFlux - Enshrouded" \
    ENS_PASSWORD= \
    ENS_SLOT_COUNT=16 \
    ENS_QUERY_PORT=15637 \
    ENS_IP=0.0.0.0 \
    ENS_GAME_SETTINGS_PRESET=Default \
    ENS_ENABLE_VOICE_CHAT=false \
    ENS_ENABLE_TEXT_CHAT=false \
    ENS_VOICE_CHAT_MODE=Proximity

# Advanced: optional full JSON overwrite
ENV ENS_SERVER_JSON= \
    ENS_SERVER_JSON_B64=

# Wine / Xvfb
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

# Runtime behavior
ENV ENS_EXE_NAME=enshrouded_server.exe \
    ENS_EXTRA_ARGS= \
    ENS_SHUTDOWN_GRACE=30

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

RUN mkdir -p /data /config /home/steam/enshrouded \
  && chown -R steam:steam /data /config /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /home/steam/enshrouded

# Official docs mention queryPort (default 15637/udp). Steam may also require ports per Valve.
EXPOSE 15637/udp 27015/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=25m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
