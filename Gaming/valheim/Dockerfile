# Valheim Dedicated Server (Flux-friendly, headless)
# - Uses SteamCMD to install/update the official Linux dedicated server (appid 896660)
# - /data: local cache (Steam install + SteamCMD caches) (recommended non-synced volume on Flux)
# - /config: synced config + saves/worlds (recommended g:/ on Flux)
FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.title="Valheim Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="Official Valheim dedicated server via SteamCMD, designed for Flux volumes and marketplace deployment."

ENV DEBIAN_FRONTEND=noninteractive

ENV STEAM_APP_ID=896660 \
    STEAM_INSTALL_DIR=/data/server \
    STEAM_LOGIN=anonymous \
    STEAM_PASSWORD= \
    STEAM_GUARD= \
    STEAM_BRANCH= \
    STEAM_BRANCH_PASSWORD= \
    STEAMCMD_EXTRA_ARGS= \
    STEAMCMD_HOME=/data/steam \
    STEAMCMD_LOG_FILE=/data/steam/steamcmd.log \
    STEAMCMD_VALIDATE=false \
    STEAMCMD_RETRIES=3 \
    AUTO_UPDATE=true \
    DISK_PREFLIGHT=true \
    MIN_FREE_GB=5 \
    HARDEN_FLUX_VOLUME_BROWSER=true

ENV VALHEIM_SERVER_NAME="RunOnFlux - Valheim" \
    VALHEIM_WORLD_NAME="RunOnFlux" \
    VALHEIM_PASSWORD= \
    VALHEIM_PUBLIC=true \
    VALHEIM_PORT=2456 \
    VALHEIM_SAVEDIR=/config \
    VALHEIM_CROSSPLAY=false \
    VALHEIM_STEAM_APP_ID=892970 \
    VALHEIM_WRITE_STEAM_APPID_TXT=true \
    VALHEIM_LOG_FILE= \
    VALHEIM_EXTRA_ARGS=

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     gosu \
     libatomic1 \
     procps \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /config \
  && chown -R steam:steam /data /config

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /home/steam

# Valheim uses UDP ports PORT, PORT+1, PORT+2 (default: 2456-2458)
EXPOSE 2456/udp 2457/udp 2458/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
