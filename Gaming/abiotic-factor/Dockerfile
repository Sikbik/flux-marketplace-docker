# Abiotic Factor Dedicated Server (Flux-friendly)
# - Uses SteamCMD to install/update the dedicated server (Steam tool appid 2857200)
# - Runs the Windows-only server under Wine with Xvfb
FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.title="Abiotic Factor Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="SteamCMD + Wine wrapper for Abiotic Factor Dedicated Server, designed for Flux volumes."

ENV DEBIAN_FRONTEND=noninteractive

# SteamCMD
ENV STEAM_APP_ID=2857200 \
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
    MIN_FREE_GB=20 \
    HARDEN_FLUX_VOLUME_BROWSER=false

# Flux-friendly persistence paths
# - /data: local cache (Steam install + SteamCMD cache) (recommended on Flux via a non-synced volume)
# - /config: synced config + saves (recommended on Flux via g:/)
ENV AF_SAVED_DIR=/config/Saved

# Dedicated server settings (via command-line parameters)
ENV AF_SERVER_NAME="RunOnFlux - Abiotic Factor" \
    AF_SERVER_PASSWORD= \
    AF_ADMIN_PASSWORD= \
    AF_MAX_PLAYERS=6 \
    AF_PORT=7777 \
    AF_QUERY_PORT=27015 \
    AF_WORLD_SAVE_NAME=Cascade

# Config generation (set MANAGE_CONFIG=false to manage .ini files yourself)
ENV MANAGE_CONFIG=true

# Optional: write Admin.ini from env (moderators list)
ENV AF_MODERATORS= \
    AF_MODERATORS_APPLY_MODE=always \
    AF_ADMIN_INI_RELATIVE_PATH="SaveGames/Server/Admin.ini"

# Optional: write a sandbox preset .ini and pass -SandboxIniPath=<...>
ENV AF_SANDBOX_SETTINGS_INI= \
    AF_SANDBOX_SETTINGS_INI_B64= \
    AF_SANDBOX_SETTINGS_INI_FILE= \
    AF_SANDBOX_APPLY_MODE=once \
    AF_SANDBOX_INI_RELATIVE_PATH="Config/WindowsServer/ServerSandbox.ini"

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
ENV AF_WRITE_STEAM_APPID_TXT=true \
    AF_BASE_GAME_APP_ID=427410 \
    AF_STEAM_GAME_ID=427410 \
    AF_SERVER_ARGS=

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

RUN mkdir -p /data /config /home/steam/abiotic \
  && chown -R steam:steam /data /config /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /home/steam/abiotic

# Common ports (game + query). Map UDP at minimum.
EXPOSE 7777/udp 7778/udp 27015/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
