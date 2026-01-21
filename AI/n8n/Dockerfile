FROM docker.n8n.io/n8nio/n8n:latest
ARG BASE_DIGEST
LABEL base.digest=${BASE_DIGEST}

USER root
RUN apk add --no-cache su-exec
COPY <<EOF /custom-entrypoint.sh
#!/bin/sh
chown -R node:node /home/node/.n8n 2>/dev/null || true
chmod 600 /home/node/.n8n/config 2>/dev/null || true
exec su-exec node /docker-entrypoint.sh
EOF
RUN chmod +x /custom-entrypoint.sh
ENTRYPOINT ["/custom-entrypoint.sh"]
