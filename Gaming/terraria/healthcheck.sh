#!/usr/bin/env bash
set -euo pipefail

port="${TERRARIA_PORT:-7777}"

if ! pgrep -f 'TerrariaServer\.bin\.x86_64' >/dev/null 2>&1; then
  exit 1
fi

if ! ss -lntH "( sport = :${port} )" 2>/dev/null | awk '{print $1}' | grep -q '^LISTEN$'; then
  exit 1
fi

exit 0
