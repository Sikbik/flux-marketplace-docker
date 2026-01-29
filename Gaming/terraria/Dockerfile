# Terraria Dedicated Server (Flux-friendly, headless)
# - Downloads the official Linux dedicated server package at runtime (no binaries baked into the image)
# - Uses /data for server install/cache (recommended local volume on Flux)
# - Uses /config for worlds/config (recommended synced g:/ on Flux)
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="Terraria Dedicated Server (Flux-friendly)"
LABEL org.opencontainers.image.description="Headless Terraria server wrapper designed for Flux volumes and marketplace listings."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     bash \
     ca-certificates \
     curl \
     gosu \
     iproute2 \
     procps \
     unzip \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash terraria \
  && mkdir -p /data /config \
  && chown -R terraria:terraria /data /config

# Install / update behavior
ENV AUTO_UPDATE=true \
    TERRARIA_INSTALL_DIR=/data/server \
    TERRARIA_SERVER_VERSION= \
    TERRARIA_SERVER_URL= \
    TERRARIA_WIKI_URL=https://terraria.wiki.gg/wiki/Server \
    DISK_PREFLIGHT=true \
    MIN_FREE_GB=2 \
    HARDEN_FLUX_VOLUME_BROWSER=true

# Dedicated server settings
ENV MANAGE_CONFIG=true \
    TERRARIA_CONFIG_PATH=/config/serverconfig.txt \
    TERRARIA_PORT=7777 \
    TERRARIA_WORLD_NAME="RunOnFlux World" \
    TERRARIA_WORLD_FILE= \
    TERRARIA_SERVER_PASSWORD= \
    TERRARIA_MAX_PLAYERS=16 \
    TERRARIA_MOTD="Welcome to Terraria on Flux!" \
    TERRARIA_AUTOCREATE=2 \
    TERRARIA_SEED= \
    TERRARIA_DIFFICULTY=0 \
    TERRARIA_SECURE=true \
    TERRARIA_UPNP=false \
    TERRARIA_EXTRA_ARGS=

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 healthcheck.sh /healthcheck.sh

WORKDIR /config

EXPOSE 7777/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
