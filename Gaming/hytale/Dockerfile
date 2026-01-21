FROM eclipse-temurin:25-jre-jammy

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl unzip tini python3 \
  && rm -rf /var/lib/apt/lists/*

# Optional helper to fetch Hytale server + assets (requires user OAuth device-code login).
# This binary is downloaded from the official Hytale URL at build time.
ARG TARGETARCH
RUN mkdir -p /opt/hytale \
  && if [[ -z "${TARGETARCH:-}" || "${TARGETARCH}" == "amd64" ]]; then \
      curl -fsSL -o /tmp/hytale-downloader.zip "https://downloader.hytale.com/hytale-downloader.zip"; \
      unzip -q /tmp/hytale-downloader.zip -d /tmp/hytale-downloader; \
      mv /tmp/hytale-downloader/hytale-downloader-linux-amd64 /opt/hytale/hytale-downloader; \
      chmod +x /opt/hytale/hytale-downloader; \
      rm -rf /tmp/hytale-downloader /tmp/hytale-downloader.zip; \
    else \
      echo "Skipping hytale-downloader install for TARGETARCH=${TARGETARCH}"; \
    fi

COPY entrypoint.sh /opt/hytale/entrypoint.sh
COPY hytale-auth /opt/hytale/hytale-auth
RUN chmod +x /opt/hytale/entrypoint.sh
RUN chmod +x /opt/hytale/hytale-auth

ENV DATA_DIR="/data" \
  PYTHONUNBUFFERED="1" \
  HYTALE_RUN_MODE="server" \
  HYTALE_BIND="0.0.0.0:5520" \
  HYTALE_AUTH_MODE="authenticated" \
  HYTALE_AUTH_AUTO="0" \
  HYTALE_AUTH_STATE_DIR="/data/auth" \
  HYTALE_AUTH_PROFILE_UUID="" \
  HYTALE_AUTH_PROFILE_USERNAME="" \
  HYTALE_AUTH_CLIENT_ID="hytale-server" \
  HYTALE_ACCEPT_EARLY_PLUGINS="0" \
  HYTALE_ALLOW_OP="0" \
  HYTALE_BACKUP="0" \
  HYTALE_BACKUP_DIR="/data/backups" \
  HYTALE_BACKUP_FREQUENCY="" \
  HYTALE_AUTO_DOWNLOAD="0" \
  HYTALE_AUTO_UPDATE="0" \
  HYTALE_KEEP_DOWNLOAD_ARCHIVE="0" \
  HYTALE_UPDATE_SKIP_PATTERNS="universe/**,logs/**,mods/**,.cache/**,*.json" \
  HYTALE_PATCHLINE="release" \
  HYTALE_CONSOLE_MODE="file" \
  HYTALE_CONSOLE_CLEAR_ON_START="1" \
  HYTALE_STARTUP_COMMANDS="" \
  HYTALE_STARTUP_COMMANDS_APPLY_MODE="once" \
  HYTALE_EPHEMERAL_CACHE="0" \
  HYTALE_CACHE_DIR="/tmp/hytale-cache" \
  HYTALE_EXTRA_ARGS="" \
  HYTALE_CONFIG_PATH="" \
  HYTALE_CONFIG_ENV_PREFIX="HYTALE_CFG__" \
  HYTALE_CONFIG_MODE="merge" \
  HYTALE_CONFIG_ALLOW_CREATE="0" \
  HYTALE_CONFIG_APPLY_MODE="always" \
  HYTALE_CONFIG_JSON="" \
  HYTALE_CONFIG_JSON_B64="" \
  HYTALE_CONFIG_JSON_FILE="" \
  HYTALE_SERVER_NAME="" \
  HYTALE_SERVER_NAME_CONFIG_KEY="ServerName" \
  HYTALE_WHITELIST_PATH="" \
  HYTALE_WHITELIST_MODE="replace" \
  HYTALE_WHITELIST_ALLOW_CREATE="1" \
  HYTALE_WHITELIST_APPLY_MODE="once" \
  HYTALE_WHITELIST_JSON="" \
  HYTALE_WHITELIST_JSON_B64="" \
  HYTALE_WHITELIST_JSON_FILE="" \
  HYTALE_BANS_PATH="" \
  HYTALE_BANS_MODE="replace" \
  HYTALE_BANS_ALLOW_CREATE="1" \
  HYTALE_BANS_APPLY_MODE="once" \
  HYTALE_BANS_JSON="" \
  HYTALE_BANS_JSON_B64="" \
  HYTALE_BANS_JSON_FILE="" \
  HYTALE_PERMISSIONS_PATH="" \
  HYTALE_PERMISSIONS_MODE="replace" \
  HYTALE_PERMISSIONS_ALLOW_CREATE="1" \
  HYTALE_PERMISSIONS_APPLY_MODE="once" \
  HYTALE_PERMISSIONS_JSON="" \
  HYTALE_PERMISSIONS_JSON_B64="" \
  HYTALE_PERMISSIONS_JSON_FILE="" \
  JAVA_OPTS="-Xms1G -Xmx4G"

VOLUME ["/data"]

EXPOSE 5520/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/hytale/entrypoint.sh"]
