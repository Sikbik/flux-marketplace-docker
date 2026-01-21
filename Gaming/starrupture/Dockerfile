FROM cm2network/steamcmd:root

USER root

# Wine is required because the StarRupture dedicated server is Windows-only.
RUN dpkg --add-architecture i386 \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates \
     curl \
     procps \
     python3 \
     xauth \
     winbind \
     wine \
     wine64 \
     wine32 \
     xvfb \
  && rm -rf /var/lib/apt/lists/*

ENV WINEARCH=win64 \
    WINEDEBUG=-all

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/saves"]

EXPOSE 7777/tcp 7777/udp 27015/udp

HEALTHCHECK --start-period=5m --interval=30s --timeout=5s --retries=3 \
  CMD pgrep -f 'StarRuptureServerEOS' >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
