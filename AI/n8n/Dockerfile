FROM docker.n8n.io/n8nio/n8n:latest
ARG BASE_DIGEST
LABEL base.digest=${BASE_DIGEST}

USER root
COPY <<EOF /custom-entrypoint.sh
#!/bin/sh
set -eu

chown -R node:node /home/node/.n8n 2>/dev/null || true
chmod 600 /home/node/.n8n/config 2>/dev/null || true

# Drop privileges to the `node` user using whatever is available in the base image.
if command -v su-exec >/dev/null 2>&1; then
  exec su-exec node /docker-entrypoint.sh "$@"
elif command -v gosu >/dev/null 2>&1; then
  exec gosu node /docker-entrypoint.sh "$@"
elif command -v setpriv >/dev/null 2>&1; then
  exec setpriv --reuid=node --regid=node --init-groups /docker-entrypoint.sh "$@"
elif command -v runuser >/dev/null 2>&1; then
  exec runuser -u node -- /docker-entrypoint.sh "$@"
elif command -v su >/dev/null 2>&1; then
  exec su -s /bin/sh node -c 'exec /docker-entrypoint.sh'
fi

echo "Warning: no privilege-drop tool found; running n8n as root." >&2
exec /docker-entrypoint.sh "$@"
EOF
RUN chmod +x /custom-entrypoint.sh
ENTRYPOINT ["/custom-entrypoint.sh"]
