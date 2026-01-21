FROM docker.n8n.io/n8nio/n8n:latest
ARG BASE_DIGEST
LABEL base.digest=${BASE_DIGEST}

USER root
RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    apk add --no-cache su-exec; \
  elif command -v apt-get >/dev/null 2>&1; then \
    apt-get update; \
    apt-get install -y --no-install-recommends gosu; \
    rm -rf /var/lib/apt/lists/*; \
  else \
    echo "Unsupported base image: no apk/apt-get found" >&2; \
    exit 1; \
  fi
COPY <<EOF /custom-entrypoint.sh
#!/bin/sh
chown -R node:node /home/node/.n8n 2>/dev/null || true
chmod 600 /home/node/.n8n/config 2>/dev/null || true
if command -v su-exec >/dev/null 2>&1; then
  exec su-exec node /docker-entrypoint.sh
elif command -v gosu >/dev/null 2>&1; then
  exec gosu node /docker-entrypoint.sh
fi
exec /docker-entrypoint.sh
EOF
RUN chmod +x /custom-entrypoint.sh
ENTRYPOINT ["/custom-entrypoint.sh"]
