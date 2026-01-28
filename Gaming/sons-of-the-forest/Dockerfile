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
    STEAMCMD_VALIDATE=true \
    AUTO_UPDATE=true

# Flux-friendly persistence paths
# - /data: local cache (Steam install + Wine prefix) (recommended on Flux via a non-synced volume)
# - /config: synced config + saves (recommended on Flux via g:/)
ENV SOTF_USERDATA_PATH=/config

# Config generation (set MANAGE_CONFIG=false to manage dedicatedserver.cfg yourself)
ENV MANAGE_CONFIG=true \
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
    SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST=true

# Wine
ENV WINEPREFIX=/data/wine/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    HOME=/home/steam \
    USER=steam

RUN dpkg --add-architecture i386 \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     gosu \
     procps \
     winbind \
     wine \
     wine64 \
     wine32 \
     xvfb \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /config /home/steam/sotf \
  && chown -R steam:steam /data /config /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh

WORKDIR /home/steam/sotf

# Common ports (game + query + blob sync). Protocol usage can vary by host/network;
# map UDP at minimum.
EXPOSE 8766/udp 27016/udp 9700/udp

ENTRYPOINT ["/entrypoint.sh"]

